// expo-av's capture services on the desktop, over Ion's audio device (ion/src/audio.ms): Ion owns
// the device, Neon decides what plays and when it reports. Ion's status is polled, so a playing
// sound and a running recording each tick on their own interval.

import {
	loadSound, unloadSound, playSound, pauseSound, stopSound, seekSound, setSoundVolume, setSoundMuted,
	setSoundLooping, setSoundRate, soundStatus,
	startRecording, pauseRecording, resumeRecording, stopRecording, closeRecording, recordingStatus,
} from "../../../../ion/src/audio";
import { tmpDir } from "std/os";
import {
	CaptureServices, PickReply, PickRequest, RecordingSetup, RecordingState, SoundSetup, SoundState,
	idleRecording, unloadedSound,
} from "../../api/captureServices";

const FILE_SCHEME = "file://";

// A path, or a file: uri (`file:///C:/a.wav`, `file:///home/a.wav`); any other scheme is refused by name.
export function pathOfUri(uri: string): Result<string, string> {
	if (uri.startsWith(FILE_SCHEME)) {
		const rest = uri.substring(FILE_SCHEME.length, uri.length);
		if (rest.indexOf("%") >= 0) {
			return Result.err("cannot decode the escapes in " + uri + " (no decodeURIComponent: .inbox/compiler/2026-10-15-decode-uri-component-missing.md)");
		}
		const drive = rest.length >= 3 && rest.substring(0, 1) === "/" && rest.substring(2, 3) === ":";
		return Result.ok(drive ? rest.substring(1, rest.length) : rest);
	}
	const colon = uri.indexOf(":");
	if (colon > 1 && uri.indexOf("/") > colon) {
		return Result.err("the desktop plays files only, not " + uri.substring(0, colon) + ": uris");
	}
	return Result.ok(uri);
}

function fileUri(path: string): string {
	const slashed = path.split("\\").join("/");
	return FILE_SCHEME + (slashed.startsWith("/") ? "" : "/") + slashed;
}

class DesktopSound {
	id: int32;
	ion: int32;
	update: (state: SoundState) => void;
	every: number;
	timer: number = -1;

	constructor(id: int32, ion: int32, update: (state: SoundState) => void, every: number) {
		this.id = id;
		this.ion = ion;
		this.update = update;
		this.every = every;
	}

	// Ion answers `finished` once, so the read that sees it reports the end to the listener;
	// the state it returns carries didJustFinish false.
	state(error: string): SoundState {
		const read = soundStatus(this.ion);
		if (!read.ok) { return unloadedSound(read.error); }
		const s = read.value;
		const state: SoundState = {
			isLoaded: true,
			isPlaying: s.playing,
			isBuffering: false,
			positionMillis: s.positionMs,
			durationMillis: s.durationMs,
			didJustFinish: false,
			isLooping: s.looping,
			volume: s.volume,
			isMuted: s.muted,
			rate: s.rate,
			error,
		};
		if (s.finished) {
			this.stopTicking();
			this.update({ ...state, didJustFinish: true });
		}
		return state;
	}

	tick(): void {
		const state = this.state("");
		if (!state.isLoaded || !state.isPlaying) {
			this.stopTicking();
			return;
		}
		this.update(state);
	}

	stopTicking(): void {
		if (this.timer < 0) { return; }
		clearInterval(this.timer);
		this.timer = -1;
	}

	startTicking(): void {
		this.stopTicking();
		this.timer = setInterval((): void => { this.tick(); }, this.every);
	}
}

const sounds: DesktopSound[] = [];

function findSound(id: int32): DesktopSound | null {
	for (const sound of sounds) {
		if (sound.id === id) { return sound; }
	}
	return null;
}

function setUp(ion: int32, setup: SoundSetup): Result<void, string> {
	try setSoundVolume(ion, setup.volume);
	try setSoundMuted(ion, setup.isMuted);
	try setSoundLooping(ion, setup.isLooping);
	try setSoundRate(ion, setup.rate);
	if (setup.positionMillis > 0) { try seekSound(ion, setup.positionMillis); }
	if (setup.shouldPlay) { try playSound(ion); }
	return Result.ok(null);
}

async function soundLoad(id: int32, setup: SoundSetup, update: (state: SoundState) => void): Promise<SoundState> {
	const previous = findSound(id);
	if (previous !== null) { soundCommand(id, "unload", 0); }
	const path = pathOfUri(setup.uri);
	if (!path.ok) { return unloadedSound("Sound.loadAsync: " + path.error); }
	const loaded = loadSound(path.value);
	if (!loaded.ok) { return unloadedSound("Sound.loadAsync: " + loaded.error); }
	const ready = setUp(loaded.value, setup);
	if (!ready.ok) {
		unloadSound(loaded.value);
		return unloadedSound("Sound.loadAsync: " + ready.error);
	}
	const sound = new DesktopSound(id, loaded.value, update, setup.progressUpdateIntervalMillis);
	sounds.push(sound);
	if (setup.shouldPlay) { sound.startTicking(); }
	return sound.state("");
}

function act(sound: DesktopSound, command: string, value: number): Result<void, string> {
	const ion = sound.ion;
	if (command === "play") {
		try playSound(ion);
		sound.startTicking();
	} else if (command === "pause") {
		try pauseSound(ion);
		sound.stopTicking();
	} else if (command === "stop") {
		try stopSound(ion);
		sound.stopTicking();
	} else if (command === "seek") {
		try seekSound(ion, value);
	} else if (command === "volume") {
		try setSoundVolume(ion, value);
	} else if (command === "loop") {
		try setSoundLooping(ion, value === 1);
	} else if (command === "mute") {
		try setSoundMuted(ion, value === 1);
	} else if (command === "rate") {
		try setSoundRate(ion, value);
	} else if (command === "interval") {
		sound.every = value;
		if (sound.timer >= 0) { sound.startTicking(); }
	} else if (command !== "status") {
		throw new Error(`Sound: the desktop host has no command "${command}"`);
	}
	return Result.ok(null);
}

function soundCommand(id: int32, command: string, value: number): SoundState {
	const found = findSound(id);
	if (found === null) { return unloadedSound("Sound: no loaded sound " + id.toString()); }
	const sound = found as DesktopSound;
	if (command === "unload") {
		sound.stopTicking();
		sounds.splice(sounds.indexOf(sound), 1);
		const unloaded = unloadSound(sound.ion);
		return unloadedSound(unloaded.ok ? "" : unloaded.error);
	}
	const done = act(sound, command, value);
	return sound.state(done.ok ? "" : done.error);
}

async function audioMode(allowsRecording: boolean, playsInSilentMode: boolean): Promise<string> {
	return "";
}

async function pickMedia(request: PickRequest): Promise<PickReply> {
	return { canceled: false, assets: [], error: "ImagePicker: the desktop host has no media picker" };
}

const RECORDED_EXTENSION = ".wav";

class DesktopRecording {
	id: int32;
	path: string;
	setup: RecordingSetup;
	update: (state: RecordingState) => void;
	every: number;
	ion: int32 = -1;
	recording: boolean = false;
	done: boolean = false;
	durationMillis: number = 0;
	timer: number = -1;

	constructor(id: int32, path: string, setup: RecordingSetup, update: (state: RecordingState) => void) {
		this.id = id;
		this.path = path;
		this.setup = setup;
		this.update = update;
		this.every = setup.progressUpdateIntervalMillis;
	}

	state(error: string): RecordingState {
		if (this.ion >= 0 && !this.done) {
			const read = recordingStatus(this.ion);
			if (!read.ok) { return idleRecording(read.error); }
			this.recording = read.value.recording;
			this.durationMillis = read.value.durationMs;
		}
		return {
			canRecord: !this.done,
			isRecording: this.recording,
			isDoneRecording: this.done,
			durationMillis: this.durationMillis,
			uri: fileUri(this.path),
			error,
		};
	}

	stopTicking(): void {
		if (this.timer < 0) { return; }
		clearInterval(this.timer);
		this.timer = -1;
	}

	startTicking(): void {
		this.stopTicking();
		this.timer = setInterval((): void => { this.update(this.state("")); }, this.every);
	}
}

const recordings: DesktopRecording[] = [];

function findRecording(id: int32): DesktopRecording | null {
	for (const recording of recordings) {
		if (recording.id === id) { return recording; }
	}
	return null;
}

async function recordingPrepare(id: int32, setup: RecordingSetup, update: (state: RecordingState) => void): Promise<RecordingState> {
	if (setup.extension !== RECORDED_EXTENSION) {
		return idleRecording(`Recording: the desktop records ${RECORDED_EXTENSION} only, not ${setup.extension}; pass extension: "${RECORDED_EXTENSION}"`);
	}
	if (findRecording(id) !== null) { return idleRecording("Recording: recording " + id.toString() + " is already prepared"); }
	const dir = tmpDir().split("\\").join("/");
	const path = (dir.endsWith("/") ? dir : dir + "/") + "neon-recording-" + id.toString() + "-" + Math.floor(Date.now()).toString() + RECORDED_EXTENSION;
	const recording = new DesktopRecording(id, path, setup, update);
	recordings.push(recording);
	return recording.state("");
}

function record(recording: DesktopRecording, command: string, value: number): Result<void, string> {
	if (command === "start") {
		if (recording.ion < 0) {
			recording.ion = try startRecording(recording.path, recording.setup.sampleRate as int32, recording.setup.numberOfChannels as int32);
		} else {
			try resumeRecording(recording.ion);
		}
		recording.startTicking();
	} else if (command === "pause") {
		if (recording.ion >= 0) { try pauseRecording(recording.ion); }
		recording.stopTicking();
	} else if (command === "stop") {
		recording.stopTicking();
		if (recording.ion >= 0) {
			try stopRecording(recording.ion);
			recording.state("");
			recording.done = true;
			recording.recording = false;
			try closeRecording(recording.ion);
		} else {
			recording.done = true;
		}
		recordings.splice(recordings.indexOf(recording), 1);
	} else if (command === "interval") {
		recording.every = value;
		if (recording.timer >= 0) { recording.startTicking(); }
	} else if (command !== "status") {
		throw new Error(`Recording: the desktop host has no command "${command}"`);
	}
	return Result.ok(null);
}

async function recordingCommand(id: int32, command: string, value: number): Promise<RecordingState> {
	const found = findRecording(id);
	if (found === null) { return idleRecording("Recording: no prepared recording " + id.toString()); }
	const recording = found as DesktopRecording;
	const done = record(recording, command, value);
	if (!done.ok) { return { ...recording.state(""), error: done.error }; }
	return recording.state("");
}

export const ionCaptureServices: CaptureServices = {
	pickMedia,
	soundLoad,
	soundCommand,
	audioMode,
	recordingPrepare,
	recordingCommand,
};
