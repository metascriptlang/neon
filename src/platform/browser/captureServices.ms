import {
	CaptureServices, PickReply, PickRequest, PickedAsset, RecordingSetup, RecordingState, SoundSetup, SoundState,
	idleRecording, unloadedSound,
} from "../../api/captureServices";
import { TextSlot } from "../../api/replySlot";

extern class Event {}

extern class File {
	name: string;
	size: number;
	type: string;
}

extern class HTMLInputElement {
	accept: cstring;
	multiple: boolean;
	extern setAttribute(name: cstring, value: cstring): void;
	extern addEventListener(name: cstring, handler: (e: Event) => void): void;
	extern click(): void;
	extern remove(): void;
}

extern class HTMLAudioElement {
	src: cstring;
	volume: number;
	muted: boolean;
	loop: boolean;
	playbackRate: number;
	currentTime: number;
	paused: boolean;
	extern pause(): void;
	extern load(): void;
	extern removeAttribute(name: cstring): void;
	extern addEventListener(name: cstring, handler: (e: Event) => void): void;
}

extern class MediaRecorder {
	state: string;
	extern start(): void;
	extern pause(): void;
	extern resume(): void;
}

extern function createFileInput(unused: int32): HTMLInputElement from "(#, (() => { const i = document.createElement('input'); i.type = 'file'; i.style.display = 'none'; i.setAttribute('data-neon-picker', ''); document.body.appendChild(i); return i; })())";
extern function inputFiles(input: HTMLInputElement): File[] from "Array.from(#.files || [])";
extern function objectUrl(file: File): string from "URL.createObjectURL(#)";
extern function describeImage(url: cstring, quality: number, base64: boolean, done: (record: string) => void): void from "((url, quality, base64, done) => { const F = String.fromCharCode(31); const img = new Image(); img.onload = () => { const w = img.naturalWidth, h = img.naturalHeight; if (quality >= 1 && !base64) { done([url, w, h, ''].join(F)); return; } const c = document.createElement('canvas'); c.width = w; c.height = h; c.getContext('2d').drawImage(img, 0, 0); const data = c.toDataURL('image/jpeg', quality); done([quality < 1 ? data : url, w, h, base64 ? data.slice(data.indexOf(',') + 1) : ''].join(F)); }; img.onerror = () => done('!cannot read the picked image'); img.src = url; })(#, #, #, #)";
extern function describeVideo(url: cstring, done: (record: string) => void): void from "((url, done) => { const F = String.fromCharCode(31); const v = document.createElement('video'); v.preload = 'metadata'; v.muted = true; v.onloadedmetadata = () => done([url, v.videoWidth, v.videoHeight, Number.isFinite(v.duration) ? Math.round(v.duration * 1000) : ''].join(F)); v.onerror = () => done([url, '', '', ''].join(F)); v.src = url; })(#, #)";
extern function createAudio(unused: int32): HTMLAudioElement from "(#, new Audio())";
extern function mediaSeconds(value: number): number from "((v) => Number.isFinite(v) ? v : 0)(#)";
extern function playAudio(audio: HTMLAudioElement, failed: (message: string) => void): void from "((a, f) => { const p = a.play(); if (p) p.catch((e) => f(String((e && e.message) || e))); })(#, #)";
extern function audioErrorMessage(audio: HTMLAudioElement): string from "((a) => a.error ? (a.error.message || 'media error ' + a.error.code) : 'the audio failed')(#)";
extern function openRecorder(done: (recorder: MediaRecorder | null, error: string) => void): void from "((done) => { if (!navigator.mediaDevices || typeof MediaRecorder === 'undefined') { done(null, 'Recording: this browser cannot record audio'); return; } navigator.mediaDevices.getUserMedia({ audio: true }).then((stream) => { const r = new MediaRecorder(stream); r.__neonChunks = []; r.ondataavailable = (e) => { if (e.data && e.data.size) r.__neonChunks.push(e.data); }; done(r, ''); }, (e) => done(null, e && e.name === 'NotAllowedError' ? 'Recording: the microphone permission is not granted' : 'Recording: ' + String((e && e.message) || e))); })(#)";
extern function stopRecorder(recorder: MediaRecorder, done: (uri: string) => void): void from "((r, done) => { const finish = () => { r.stream.getTracks().forEach((t) => t.stop()); done(URL.createObjectURL(new Blob(r.__neonChunks, { type: r.mimeType || 'audio/webm' }))); }; if (r.state === 'inactive') { finish(); return; } r.onstop = finish; r.stop(); })(#, #)";
extern function releaseRecorder(recorder: MediaRecorder): void from "((r) => { if (r.state !== 'inactive') r.stop(); r.stream.getTracks().forEach((t) => t.stop()); })(#)";

const FIELD = "\u001f";

let picking = false;

function accept(request: PickRequest): string {
	if (request.images && request.videos) { return "image/*,video/*"; }
	return request.videos ? "video/*" : "image/*";
}

function number(text: string): number {
	return text === "" ? -1 : parseFloat(text);
}

async function describe(file: File, request: PickRequest): Promise<PickedAsset> {
	const slot = new TextSlot();
	const url = objectUrl(file);
	const video = file.type.startsWith("video/");
	if (video) {
		describeVideo(url, (record: string): void => { slot.settle(record); });
	} else {
		describeImage(url, request.quality, request.base64, (record: string): void => { slot.settle(record); });
	}
	const record = await slot.wait();
	if (record.startsWith("!")) { throw new Error("ImagePicker: " + record.substring(1, record.length)); }
	const fields = record.split(FIELD);
	const reencoded = fields[0].startsWith("data:");
	return {
		uri: fields[0],
		width: number(fields[1]),
		height: number(fields[2]),
		type: video ? "video" : "image",
		fileName: file.name,
		fileSize: reencoded ? -1 : file.size,
		mimeType: reencoded ? "image/jpeg" : file.type,
		duration: video ? number(fields[3]) : -1,
		base64: video ? "" : fields[3],
	};
}

async function pickMedia(request: PickRequest): Promise<PickReply> {
	if (picking) { return { canceled: false, assets: [], error: "ImagePicker: another picker is already open" }; }
	picking = true;
	const input = createFileInput(0);
	input.accept = accept(request);
	input.multiple = request.multiple;
	if (request.camera) { input.setAttribute("capture", request.cameraType === "front" ? "user" : "environment"); }
	const chosen = new TextSlot();
	input.addEventListener("change", (e: Event): void => { chosen.settle("change"); });
	input.addEventListener("cancel", (e: Event): void => { chosen.settle("cancel"); });
	input.click();
	const outcome = await chosen.wait();
	const files = outcome === "change" ? inputFiles(input) : [];
	input.remove();
	const assets: PickedAsset[] = [];
	const limit = request.multiple && request.selectionLimit > 0 ? request.selectionLimit : (request.multiple ? files.length : 1);
	try {
		for (let i = 0; i < files.length && i < limit; i += 1) { assets.push(await describe(files[i], request)); }
	} catch (e) {
		picking = false;
		return { canceled: false, assets: [], error: (e as Error).message };
	}
	picking = false;
	return { canceled: assets.length === 0, assets, error: "" };
}

class BrowserSound {
	id: int32;
	el: HTMLAudioElement;
	update: (state: SoundState) => void;
	every: number;
	timer: number = -1;
	loaded: boolean = false;
	finished: boolean = false;
	failure: string = "";

	constructor(id: int32, el: HTMLAudioElement, update: (state: SoundState) => void, every: number) {
		this.id = id;
		this.el = el;
		this.update = update;
		this.every = every;
	}

	state(): SoundState {
		const el = this.el;
		const duration = mediaSeconds(durationOf(el)) * 1000;
		return {
			isLoaded: this.loaded,
			isPlaying: this.loaded && !el.paused,
			isBuffering: false,
			positionMillis: this.finished ? duration : Math.round(el.currentTime * 1000),
			durationMillis: Math.round(duration),
			didJustFinish: this.finished,
			isLooping: el.loop,
			volume: el.volume,
			isMuted: el.muted,
			rate: el.playbackRate,
			error: this.failure,
		};
	}

	report(): void {
		if (!this.loaded) { return; }
		this.update(this.state());
	}

	stopTicking(): void {
		if (this.timer < 0) { return; }
		clearInterval(this.timer);
		this.timer = -1;
	}

	startTicking(): void {
		this.stopTicking();
		this.timer = setInterval((): void => { this.report(); }, this.every);
	}
}

extern function durationOf(audio: HTMLAudioElement): number from "#.duration";

const sounds: BrowserSound[] = [];

function findSound(id: int32): BrowserSound | null {
	for (const sound of sounds) {
		if (sound.id === id) { return sound; }
	}
	return null;
}

async function soundLoad(id: int32, setup: SoundSetup, update: (state: SoundState) => void): Promise<SoundState> {
	const el = createAudio(0);
	const sound = new BrowserSound(id, el, update, setup.progressUpdateIntervalMillis);
	const loaded = new TextSlot();
	el.addEventListener("loadedmetadata", (e: Event): void => { loaded.settle(""); });
	el.addEventListener("error", (e: Event): void => {
		if (!sound.loaded) {
			loaded.settle(audioErrorMessage(el));
			return;
		}
		sound.failure = audioErrorMessage(el);
		sound.report();
	});
	el.addEventListener("play", (e: Event): void => {
		sound.finished = false;
		sound.startTicking();
	});
	el.addEventListener("pause", (e: Event): void => { sound.stopTicking(); });
	el.addEventListener("ended", (e: Event): void => {
		sound.stopTicking();
		sound.finished = true;
		sound.report();
		sound.finished = false;
	});
	el.volume = setup.volume;
	el.muted = setup.isMuted;
	el.loop = setup.isLooping;
	el.playbackRate = setup.rate;
	el.src = setup.uri;
	const failure = await loaded.wait();
	if (failure !== "") {
		return unloadedSound("Sound.loadAsync: cannot load " + setup.uri + ": " + failure);
	}
	sound.loaded = true;
	sounds.push(sound);
	if (setup.positionMillis > 0) { el.currentTime = setup.positionMillis / 1000; }
	if (setup.shouldPlay) { start(sound); }
	return sound.state();
}

function start(sound: BrowserSound): void {
	sound.finished = false;
	playAudio(sound.el, (message: string): void => {
		sound.failure = "Sound.playAsync: " + message;
		sound.report();
		sound.failure = "";
	});
}

function soundCommand(id: int32, command: string, value: number): SoundState {
	const found = findSound(id);
	if (found === null) { return unloadedSound("Sound: no loaded sound " + id.toString()); }
	const sound = found as BrowserSound;
	const el = sound.el;
	if (command === "play") {
		start(sound);
		const state = sound.state();
		state.isPlaying = true;
		return state;
	}
	if (command === "pause") { el.pause(); }
	else if (command === "stop") {
		el.pause();
		el.currentTime = 0;
	}
	else if (command === "seek") {
		sound.finished = false;
		el.currentTime = value / 1000;
	}
	else if (command === "volume") { el.volume = value; }
	else if (command === "loop") { el.loop = value === 1; }
	else if (command === "mute") { el.muted = value === 1; }
	else if (command === "rate") { el.playbackRate = value; }
	else if (command === "interval") {
		sound.every = value;
		if (sound.timer >= 0) { sound.startTicking(); }
	}
	else if (command === "unload") {
		sound.stopTicking();
		el.pause();
		el.removeAttribute("src");
		el.load();
		sound.loaded = false;
		sounds.splice(sounds.indexOf(sound), 1);
		return unloadedSound("");
	}
	else if (command !== "status") { throw new Error(`Sound: the browser host has no command "${command}"`); }
	const state = sound.state();
	if (command === "pause" || command === "stop") { state.isPlaying = false; }
	return state;
}

async function audioMode(allowsRecording: boolean, playsInSilentMode: boolean): Promise<string> {
	return "";
}

class BrowserRecording {
	id: int32;
	recorder: MediaRecorder;
	update: (state: RecordingState) => void;
	every: number;
	timer: number = -1;
	elapsed: number = 0;
	resumedAt: number = -1;
	done: boolean = false;
	uri: string = "";

	constructor(id: int32, recorder: MediaRecorder, update: (state: RecordingState) => void, every: number) {
		this.id = id;
		this.recorder = recorder;
		this.update = update;
		this.every = every;
	}

	duration(): number {
		return Math.round(this.elapsed + (this.resumedAt < 0 ? 0 : performance.now() - this.resumedAt));
	}

	state(): RecordingState {
		return {
			canRecord: !this.done,
			isRecording: this.resumedAt >= 0,
			isDoneRecording: this.done,
			durationMillis: this.duration(),
			uri: this.uri,
			error: "",
		};
	}

	stopTicking(): void {
		if (this.timer < 0) { return; }
		clearInterval(this.timer);
		this.timer = -1;
	}

	startTicking(): void {
		this.stopTicking();
		this.timer = setInterval((): void => { this.update(this.state()); }, this.every);
	}

	hold(): void {
		if (this.resumedAt >= 0) {
			this.elapsed += performance.now() - this.resumedAt;
			this.resumedAt = -1;
		}
		this.stopTicking();
	}
}

const recordings: BrowserRecording[] = [];

function findRecording(id: int32): BrowserRecording | null {
	for (const recording of recordings) {
		if (recording.id === id) { return recording; }
	}
	return null;
}

async function recordingPrepare(id: int32, setup: RecordingSetup, update: (state: RecordingState) => void): Promise<RecordingState> {
	const opened = new TextSlot();
	let recorder: MediaRecorder | null = null;
	openRecorder((r: MediaRecorder | null, error: string): void => {
		recorder = r;
		opened.settle(error);
	});
	const error = await opened.wait();
	if (error !== "" || recorder === null) { return idleRecording(error === "" ? "Recording: no recorder" : error); }
	const recording = new BrowserRecording(id, recorder as MediaRecorder, update, setup.progressUpdateIntervalMillis);
	recordings.push(recording);
	return recording.state();
}

async function recordingCommand(id: int32, command: string, value: number): Promise<RecordingState> {
	const found = findRecording(id);
	if (found === null) { return idleRecording("Recording: no prepared recording " + id.toString()); }
	const recording = found as BrowserRecording;
	const recorder = recording.recorder;
	if (command === "start") {
		if (recorder.state === "paused") { recorder.resume(); } else if (recorder.state === "inactive") { recorder.start(); }
		recording.resumedAt = performance.now();
		recording.startTicking();
	} else if (command === "pause") {
		if (recorder.state === "recording") { recorder.pause(); }
		recording.hold();
	} else if (command === "stop") {
		recording.hold();
		const stopped = new TextSlot();
		stopRecorder(recorder, (uri: string): void => { stopped.settle(uri); });
		recording.uri = await stopped.wait();
		recording.done = true;
		recordings.splice(recordings.indexOf(recording), 1);
	} else if (command === "interval") {
		recording.every = value;
		if (recording.timer >= 0) { recording.startTicking(); }
	} else if (command !== "status") {
		releaseRecorder(recorder);
		throw new Error(`Recording: the browser host has no command "${command}"`);
	}
	return recording.state();
}

export const browserCaptureServices: CaptureServices = {
	pickMedia,
	soundLoad,
	soundCommand,
	audioMode,
	recordingPrepare,
	recordingCommand,
};
