import { ionCaptureServices, pathOfUri } from "../../src/platform/ion/audio";
import { RecordingState, SoundSetup, SoundState } from "../../src/api/captureServices";

function mapped(uri: string): string {
	const path = pathOfUri(uri);
	return path.ok ? path.value : "error " + path.error;
}

function setupOf(uri: string): SoundSetup {
	return { uri, shouldPlay: false, volume: 1, isLooping: false, isMuted: false, positionMillis: 0, rate: 1, progressUpdateIntervalMillis: 100 };
}

test "a path or a file uri becomes a path; another scheme or an escape is refused by name" {
	assert mapped("file:///C:/a b.wav") === "C:/a b.wav", mapped("file:///C:/a b.wav");
	assert mapped("file:///home/a.wav") === "/home/a.wav", mapped("file:///home/a.wav");
	assert mapped("C:/sounds/a.wav") === "C:/sounds/a.wav", mapped("C:/sounds/a.wav");
	assert mapped("sounds/a.wav") === "sounds/a.wav", mapped("sounds/a.wav");
	assert mapped("https://x/a.wav") === "error the desktop plays files only, not https: uris", mapped("https://x/a.wav");
	assert mapped("data:audio/wav;base64,AA") === "error the desktop plays files only, not data: uris", mapped("data:audio/wav;base64,AA");
	assert mapped("file:///C:/a%20b.wav").startsWith("error cannot decode the escapes"), mapped("file:///C:/a%20b.wav");
}

test "a sound from another scheme does not load, and names why" {
	const state = await ionCaptureServices.soundLoad(1, setupOf("https://x/a.wav"), (s: SoundState): void => {});
	assert !state.isLoaded, "loaded";
	assert state.error === "Sound.loadAsync: the desktop plays files only, not https: uris", state.error;
	assert ionCaptureServices.soundCommand(1, "status", 0).error === "Sound: no loaded sound 1", "unknown sound";
}

test "the desktop records .wav only, and an m4a preset is refused before the device opens" {
	const none = (r: RecordingState): void => {};
	const m4a = await ionCaptureServices.recordingPrepare(1, { extension: ".m4a", sampleRate: 44100, numberOfChannels: 2, bitRate: 128000, progressUpdateIntervalMillis: 100 }, none);
	assert m4a.error === `Recording: the desktop records .wav only, not .m4a; pass extension: ".wav"`, m4a.error;
	const wav = await ionCaptureServices.recordingPrepare(2, { extension: ".wav", sampleRate: 44100, numberOfChannels: 1, bitRate: 0, progressUpdateIntervalMillis: 100 }, none);
	assert wav.error === "" && wav.canRecord && !wav.isRecording, wav.error;
	assert wav.uri.startsWith("file:///") && wav.uri.endsWith(".wav"), wav.uri;
	const stopped = await ionCaptureServices.recordingCommand(2, "stop", 0);
	assert stopped.isDoneRecording && stopped.error === "", stopped.error;
}
