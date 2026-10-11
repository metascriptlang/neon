// Host refusals travel as `error` values, not as throws inside a service: on C a rejection awaited
// through a function value is lost (compiler card 2026-10-08-await-through-a-function-field-drops-the-rejection-on-c.md).

export interface PickRequest {
	camera: boolean;
	images: boolean;
	videos: boolean;
	allowsEditing: boolean;
	quality: number;
	base64: boolean;
	multiple: boolean;
	selectionLimit: int32;
	cameraType: string;
}

// "" marks a text field the host does not report, -1 a number.
export interface PickedAsset {
	uri: string;
	width: number;
	height: number;
	type: string;
	fileName: string;
	fileSize: number;
	mimeType: string;
	duration: number;
	base64: string;
}

export interface PickReply {
	canceled: boolean;
	assets: PickedAsset[];
	error: string;
}

export interface SoundSetup {
	uri: string;
	shouldPlay: boolean;
	volume: number;
	isLooping: boolean;
	isMuted: boolean;
	positionMillis: number;
	rate: number;
	progressUpdateIntervalMillis: number;
}

export interface SoundState {
	isLoaded: boolean;
	isPlaying: boolean;
	isBuffering: boolean;
	positionMillis: number;
	durationMillis: number;
	didJustFinish: boolean;
	isLooping: boolean;
	volume: number;
	isMuted: boolean;
	rate: number;
	error: string;
}

export interface RecordingSetup {
	extension: string;
	sampleRate: number;
	numberOfChannels: number;
	bitRate: number;
	progressUpdateIntervalMillis: number;
}

export interface RecordingState {
	canRecord: boolean;
	isRecording: boolean;
	isDoneRecording: boolean;
	durationMillis: number;
	uri: string;
	error: string;
}

export interface CaptureServices {
	pickMedia: (request: PickRequest) => Promise<PickReply>;
	soundLoad: (id: int32, setup: SoundSetup, update: (state: SoundState) => void) => Promise<SoundState>;
	// Commands: play, pause, stop, seek (ms), volume, loop (1/0), mute (1/0), rate, interval (ms), status, unload.
	soundCommand: (id: int32, command: string, value: number) => SoundState;
	audioMode: (allowsRecording: boolean, playsInSilentMode: boolean) => Promise<string>;
	recordingPrepare: (id: int32, setup: RecordingSetup, update: (state: RecordingState) => void) => Promise<RecordingState>;
	// Commands: start, pause, stop, status, interval (ms).
	recordingCommand: (id: int32, command: string, value: number) => Promise<RecordingState>;
}

let installed: CaptureServices | null = null;

export function installCaptureServices(services: CaptureServices | null): void {
	installed = services;
}

export function captureServices(api: string): CaptureServices {
	const services = installed;
	if (services === null) {
		throw new Error(api + ": no host has installed capture services; start the app through runApp or domHost");
	}
	return services;
}

export function unloadedSound(error: string): SoundState {
	return {
		isLoaded: false,
		isPlaying: false,
		isBuffering: false,
		positionMillis: 0,
		durationMillis: 0,
		didJustFinish: false,
		isLooping: false,
		volume: 1,
		isMuted: false,
		rate: 1,
		error,
	};
}

export function idleRecording(error: string): RecordingState {
	return { canRecord: false, isRecording: false, isDoneRecording: false, durationMillis: 0, uri: "", error };
}
