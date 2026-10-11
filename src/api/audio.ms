import {
	RecordingSetup, RecordingState, SoundSetup, SoundState, captureServices, unloadedSound,
} from "./captureServices";
import { Permissions, PermissionResponse } from "./permissions";

export interface AVPlaybackSource {
	uri: string;
}

export interface AVPlaybackStatusToSet {
	shouldPlay?: boolean | null;
	volume?: number | null;
	isLooping?: boolean | null;
	isMuted?: boolean | null;
	positionMillis?: number | null;
	rate?: number | null;
	progressUpdateIntervalMillis?: number | null;
}

export interface AVPlaybackStatus {
	isLoaded: boolean;
	uri: string;
	isPlaying: boolean;
	isBuffering: boolean;
	shouldPlay: boolean;
	positionMillis: number;
	durationMillis: number;
	didJustFinish: boolean;
	isLooping: boolean;
	volume: number;
	isMuted: boolean;
	rate: number;
	progressUpdateIntervalMillis: number;
	error: string | null;
}

export interface SoundObject {
	sound: Sound;
	status: AVPlaybackStatus;
}

export interface RecordingStatus {
	canRecord: boolean;
	isRecording: boolean;
	isDoneRecording: boolean;
	durationMillis: number;
	uri: string | null;
	mediaServicesDidReset: boolean;
}

export interface RecordingObject {
	recording: Recording;
	status: RecordingStatus;
}

export interface RecordingOptions {
	extension?: string | null;
	sampleRate?: number | null;
	numberOfChannels?: number | null;
	bitRate?: number | null;
	isMeteringEnabled?: boolean | null;
}

export interface RecordingOptionsPresetTable {
	HIGH_QUALITY: RecordingOptions;
	LOW_QUALITY: RecordingOptions;
}

export interface AudioMode {
	allowsRecordingIOS?: boolean | null;
	playsInSilentModeIOS?: boolean | null;
	staysActiveInBackground?: boolean | null;
	shouldDuckAndroid?: boolean | null;
	playThroughEarpieceAndroid?: boolean | null;
}

const NO_STATUS: AVPlaybackStatusToSet = {};
const PROGRESS_EVERY_MS: number = 500;
const NOT_LOADED = "Cannot complete operation because sound is not loaded.";

let nextSound: int32 = 1;
let nextRecording: int32 = 1;

function playbackStatus(state: SoundState, uri: string, shouldPlay: boolean, every: number): AVPlaybackStatus {
	return {
		isLoaded: state.isLoaded,
		uri: state.isLoaded ? uri : "",
		isPlaying: state.isPlaying,
		isBuffering: state.isBuffering,
		shouldPlay,
		positionMillis: state.positionMillis,
		durationMillis: state.durationMillis,
		didJustFinish: state.didJustFinish,
		isLooping: state.isLooping,
		volume: state.volume,
		isMuted: state.isMuted,
		rate: state.rate,
		progressUpdateIntervalMillis: every,
		error: state.error === "" ? null : state.error,
	};
}

function checkVolume(volume: number): void {
	if (!(volume >= 0 && volume <= 1)) { throw new Error(`Sound: volume must be between 0 and 1, got ${volume}`); }
}

function checkRate(rate: number): void {
	if (!(rate > 0 && rate <= 32)) { throw new Error(`Sound: rate must be above 0 and at most 32, got ${rate}`); }
}

export class Sound {
	private id: int32;
	private loaded: boolean = false;
	private uri: string = "";
	private shouldPlay: boolean = false;
	private every: number = PROGRESS_EVERY_MS;
	private listener: ((status: AVPlaybackStatus) => void) | null = null;

	constructor() {
		this.id = nextSound;
		nextSound += 1;
	}

	static async createAsync(
		source: AVPlaybackSource,
		initialStatus: AVPlaybackStatusToSet = NO_STATUS,
		onPlaybackStatusUpdate: ((status: AVPlaybackStatus) => void) | null = null,
	): Promise<SoundObject> {
		const sound = new Sound();
		sound.setOnPlaybackStatusUpdate(onPlaybackStatusUpdate);
		const status = await sound.loadAsync(source, initialStatus);
		return { sound, status };
	}

	private notify(status: AVPlaybackStatus): void {
		const listener = this.listener;
		if (listener !== null) { listener(status); }
	}

	private onState(state: SoundState): void {
		if (!state.isLoaded) { this.loaded = false; }
		if (state.didJustFinish && !state.isLooping) { this.shouldPlay = false; }
		this.notify(playbackStatus(state, this.uri, this.shouldPlay, this.every));
	}

	setOnPlaybackStatusUpdate(listener: ((status: AVPlaybackStatus) => void) | null): void {
		this.listener = listener;
	}

	async loadAsync(source: AVPlaybackSource, initialStatus: AVPlaybackStatusToSet = NO_STATUS): Promise<AVPlaybackStatus> {
		if (this.loaded) { throw new Error("The Sound is already loaded."); }
		if (source.uri === "") { throw new Error("Sound.loadAsync: the source has no uri"); }
		const volume = initialStatus.volume ?? 1;
		checkVolume(volume);
		const rate = initialStatus.rate ?? 1;
		checkRate(rate);
		const every = initialStatus.progressUpdateIntervalMillis ?? PROGRESS_EVERY_MS;
		const setup: SoundSetup = {
			uri: source.uri,
			shouldPlay: initialStatus.shouldPlay ?? false,
			volume,
			isLooping: initialStatus.isLooping ?? false,
			isMuted: initialStatus.isMuted ?? false,
			positionMillis: initialStatus.positionMillis ?? 0,
			rate,
			progressUpdateIntervalMillis: every,
		};
		this.uri = source.uri;
		this.every = every;
		this.shouldPlay = setup.shouldPlay;
		const state = await captureServices("Sound.loadAsync").soundLoad(this.id, setup, (s: SoundState): void => { this.onState(s); });
		if (!state.isLoaded) {
			throw new Error(state.error === "" ? "Sound.loadAsync: the sound did not load" : state.error);
		}
		this.loaded = true;
		const status = playbackStatus(state, this.uri, this.shouldPlay, this.every);
		this.notify(status);
		return status;
	}

	private command(name: string, value: number): AVPlaybackStatus {
		if (!this.loaded) { throw new Error(NOT_LOADED); }
		const state = captureServices("Sound").soundCommand(this.id, name, value);
		if (state.error !== "" && state.isLoaded) { throw new Error(state.error); }
		const status = playbackStatus(state, this.uri, this.shouldPlay, this.every);
		this.notify(status);
		return status;
	}

	async playAsync(): Promise<AVPlaybackStatus> {
		this.shouldPlay = true;
		const status = this.command("play", 0);
		return status;
	}

	async pauseAsync(): Promise<AVPlaybackStatus> {
		this.shouldPlay = false;
		const status = this.command("pause", 0);
		return status;
	}

	async stopAsync(): Promise<AVPlaybackStatus> {
		this.shouldPlay = false;
		const status = this.command("stop", 0);
		return status;
	}

	async setPositionAsync(positionMillis: number): Promise<AVPlaybackStatus> {
		if (!(positionMillis >= 0)) { throw new Error(`Sound.setPositionAsync needs 0 or more milliseconds, got ${positionMillis}`); }
		const status = this.command("seek", positionMillis);
		return status;
	}

	async playFromPositionAsync(positionMillis: number): Promise<AVPlaybackStatus> {
		await this.setPositionAsync(positionMillis);
		const status = await this.playAsync();
		return status;
	}

	async replayAsync(): Promise<AVPlaybackStatus> {
		const status = await this.playFromPositionAsync(0);
		return status;
	}

	async setVolumeAsync(volume: number): Promise<AVPlaybackStatus> {
		checkVolume(volume);
		const status = this.command("volume", volume);
		return status;
	}

	async setIsLoopingAsync(isLooping: boolean): Promise<AVPlaybackStatus> {
		const status = this.command("loop", isLooping ? 1 : 0);
		return status;
	}

	async setIsMutedAsync(isMuted: boolean): Promise<AVPlaybackStatus> {
		const status = this.command("mute", isMuted ? 1 : 0);
		return status;
	}

	async setRateAsync(rate: number): Promise<AVPlaybackStatus> {
		checkRate(rate);
		const status = this.command("rate", rate);
		return status;
	}

	async setProgressUpdateIntervalAsync(progressUpdateIntervalMillis: number): Promise<AVPlaybackStatus> {
		if (!(progressUpdateIntervalMillis > 0)) {
			throw new Error(`Sound.setProgressUpdateIntervalAsync needs a positive interval, got ${progressUpdateIntervalMillis}`);
		}
		this.every = progressUpdateIntervalMillis;
		const status = this.command("interval", progressUpdateIntervalMillis);
		return status;
	}

	async setStatusAsync(status: AVPlaybackStatusToSet): Promise<AVPlaybackStatus> {
		if (status.volume !== null && status.volume !== undefined) { await this.setVolumeAsync(status.volume as number); }
		if (status.rate !== null && status.rate !== undefined) { await this.setRateAsync(status.rate as number); }
		if (status.isLooping !== null && status.isLooping !== undefined) { await this.setIsLoopingAsync(status.isLooping as boolean); }
		if (status.isMuted !== null && status.isMuted !== undefined) { await this.setIsMutedAsync(status.isMuted as boolean); }
		if (status.positionMillis !== null && status.positionMillis !== undefined) {
			await this.setPositionAsync(status.positionMillis as number);
		}
		if (status.shouldPlay !== null && status.shouldPlay !== undefined) {
			if (status.shouldPlay as boolean) { await this.playAsync(); } else { await this.pauseAsync(); }
		}
		const now = await this.getStatusAsync();
		return now;
	}

	async getStatusAsync(): Promise<AVPlaybackStatus> {
		if (!this.loaded) { return playbackStatus(unloadedSound(""), "", false, this.every); }
		const state = captureServices("Sound").soundCommand(this.id, "status", 0);
		return playbackStatus(state, this.uri, this.shouldPlay, this.every);
	}

	async unloadAsync(): Promise<AVPlaybackStatus> {
		if (!this.loaded) { return playbackStatus(unloadedSound(""), "", false, this.every); }
		this.loaded = false;
		this.shouldPlay = false;
		captureServices("Sound").soundCommand(this.id, "unload", 0);
		const status = playbackStatus(unloadedSound(""), "", false, this.every);
		this.notify(status);
		return status;
	}
}

function recordingStatus(state: RecordingState): RecordingStatus {
	return {
		canRecord: state.canRecord,
		isRecording: state.isRecording,
		isDoneRecording: state.isDoneRecording,
		durationMillis: state.durationMillis,
		uri: state.uri === "" ? null : state.uri,
		mediaServicesDidReset: false,
	};
}

const HIGH_QUALITY: RecordingOptions = { extension: ".m4a", sampleRate: 44100, numberOfChannels: 2, bitRate: 128000 };
const LOW_QUALITY: RecordingOptions = { extension: ".m4a", sampleRate: 44100, numberOfChannels: 1, bitRate: 64000 };

export class Recording {
	private id: int32;
	private prepared: boolean = false;
	private done: boolean = false;
	private uri: string = "";
	private every: number = PROGRESS_EVERY_MS;
	private listener: ((status: RecordingStatus) => void) | null = null;

	constructor() {
		this.id = nextRecording;
		nextRecording += 1;
	}

	static async createAsync(
		options: RecordingOptions = HIGH_QUALITY,
		onRecordingStatusUpdate: ((status: RecordingStatus) => void) | null = null,
		progressUpdateIntervalMillis: number = PROGRESS_EVERY_MS,
	): Promise<RecordingObject> {
		const recording = new Recording();
		recording.setOnRecordingStatusUpdate(onRecordingStatusUpdate);
		recording.setProgressUpdateInterval(progressUpdateIntervalMillis);
		await recording.prepareToRecordAsync(options);
		const status = await recording.startAsync();
		return { recording, status };
	}

	private notify(status: RecordingStatus): void {
		const listener = this.listener;
		if (listener !== null) { listener(status); }
	}

	private onState(state: RecordingState): void {
		if (state.uri !== "") { this.uri = state.uri; }
		this.notify(recordingStatus(state));
	}

	setOnRecordingStatusUpdate(listener: ((status: RecordingStatus) => void) | null): void {
		this.listener = listener;
	}

	setProgressUpdateInterval(progressUpdateIntervalMillis: number): void {
		if (!(progressUpdateIntervalMillis > 0)) {
			throw new Error(`Recording.setProgressUpdateInterval needs a positive interval, got ${progressUpdateIntervalMillis}`);
		}
		this.every = progressUpdateIntervalMillis;
		if (this.prepared && !this.done) {
			captureServices("Recording").recordingCommand(this.id, "interval", progressUpdateIntervalMillis);
		}
	}

	async prepareToRecordAsync(options: RecordingOptions = HIGH_QUALITY): Promise<RecordingStatus> {
		if (this.prepared) { throw new Error("This Recording object is already prepared to record."); }
		if (this.done) { throw new Error("This Recording object is done recording; you must make a new one."); }
		const permission = await Permissions.check("microphone");
		if (!permission.granted) { throw new Error("Missing audio recording permissions."); }
		const extension = options.extension ?? ".m4a";
		const setup: RecordingSetup = {
			extension: extension.startsWith(".") ? extension : "." + extension,
			sampleRate: options.sampleRate ?? 44100,
			numberOfChannels: options.numberOfChannels ?? 2,
			bitRate: options.bitRate ?? 128000,
			progressUpdateIntervalMillis: this.every,
		};
		const state = await captureServices("Recording.prepareToRecordAsync").recordingPrepare(
			this.id, setup, (s: RecordingState): void => { this.onState(s); },
		);
		if (state.error !== "") { throw new Error(state.error); }
		this.prepared = true;
		if (state.uri !== "") { this.uri = state.uri; }
		const status = recordingStatus(state);
		this.notify(status);
		return status;
	}

	private async command(name: string): Promise<RecordingStatus> {
		if (!this.prepared) {
			throw new Error(this.done ? "Cannot " + name + " a Recording that is done recording." : "Cannot " + name + " a Recording that is not prepared.");
		}
		const state = await captureServices("Recording").recordingCommand(this.id, name, 0);
		if (state.error !== "") { throw new Error(state.error); }
		if (state.uri !== "") { this.uri = state.uri; }
		const status = recordingStatus(state);
		this.notify(status);
		return status;
	}

	async startAsync(): Promise<RecordingStatus> {
		const status = await this.command("start");
		return status;
	}

	async pauseAsync(): Promise<RecordingStatus> {
		const status = await this.command("pause");
		return status;
	}

	async stopAndUnloadAsync(): Promise<RecordingStatus> {
		const status = await this.command("stop");
		this.prepared = false;
		this.done = true;
		return status;
	}

	async getStatusAsync(): Promise<RecordingStatus> {
		if (!this.prepared) {
			return {
				canRecord: false,
				isRecording: false,
				isDoneRecording: this.done,
				durationMillis: 0,
				uri: this.uri === "" ? null : this.uri,
				mediaServicesDidReset: false,
			};
		}
		const state = await captureServices("Recording").recordingCommand(this.id, "status", 0);
		return recordingStatus(state);
	}

	getURI(): string | null {
		return this.uri === "" ? null : this.uri;
	}

	async createNewLoadedSoundAsync(
		initialStatus: AVPlaybackStatusToSet = NO_STATUS,
		onPlaybackStatusUpdate: ((status: AVPlaybackStatus) => void) | null = null,
	): Promise<SoundObject> {
		if (!this.done || this.uri === "") {
			throw new Error("Cannot create a sound from a Recording that has not been stopped and unloaded.");
		}
		const made = await Sound.createAsync({ uri: this.uri }, initialStatus, onPlaybackStatusUpdate);
		return made;
	}
}

export class SoundNamespace {
	async createAsync(
		source: AVPlaybackSource,
		initialStatus: AVPlaybackStatusToSet = NO_STATUS,
		onPlaybackStatusUpdate: ((status: AVPlaybackStatus) => void) | null = null,
	): Promise<SoundObject> {
		const made = await Sound.createAsync(source, initialStatus, onPlaybackStatusUpdate);
		return made;
	}
}

export class RecordingNamespace {
	async createAsync(
		options: RecordingOptions = HIGH_QUALITY,
		onRecordingStatusUpdate: ((status: RecordingStatus) => void) | null = null,
		progressUpdateIntervalMillis: number = PROGRESS_EVERY_MS,
	): Promise<RecordingObject> {
		const made = await Recording.createAsync(options, onRecordingStatusUpdate, progressUpdateIntervalMillis);
		return made;
	}
}

export class Audio {
	static Sound: SoundNamespace = new SoundNamespace();
	static Recording: RecordingNamespace = new RecordingNamespace();
	static RecordingOptionsPresets: RecordingOptionsPresetTable = { HIGH_QUALITY, LOW_QUALITY };

	static async requestPermissionsAsync(): Promise<PermissionResponse> {
		const answered = await Permissions.request("microphone");
		return answered;
	}

	static async getPermissionsAsync(): Promise<PermissionResponse> {
		const checked = await Permissions.check("microphone");
		return checked;
	}

	static async setAudioModeAsync(mode: AudioMode): Promise<void> {
		const error = await captureServices("Audio.setAudioModeAsync").audioMode(
			mode.allowsRecordingIOS ?? false, mode.playsInSilentModeIOS ?? false,
		);
		if (error !== "") { throw new Error(error); }
	}
}
