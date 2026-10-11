import { runApp } from "../../src/platform/native/host";
import { createSignal } from "../../src/core/signal";
import { View } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { ImagePicker, ImagePickerResult } from "../../src/api/imagePicker";
import { Audio, AVPlaybackStatus, Recording, RecordingStatus, Sound } from "../../src/api/audio";
import { CameraType, CameraView, CameraViewHandle, CameraCapturedPicture, CameraMountError } from "../../src/components/cameraView";
import { sleepAsync } from "std/core/promise";
import {
	nmAppReply, nmAppLog, nmAppLogClear, nmAppEvent, nmTeardown, nmControl, nmProp, nmLastControlTag, nmLayoutWidth,
	nmLayoutHeight, nmReleaseCalls, nmViewsCreated,
} from "./nativeBridgeMock.h";

const FIELD = "\u001f";
const RECORD = "\u001e";
const REPLY: int32 = 9;
const SOUND: int32 = 13;
const RECORDING: int32 = 14;
const CAMERA: int32 = 12;

function prop(tag: int32, name: string): string {
	return nmProp(tag, name);
}

function mount(): void {
	nmAppReply("platform", "17.5");
	nmAppReply("pixelRatio", "3");
	nmAppReply("fontScale", "1");
	nmAppReply("screen", "393" + FIELD + "852");
	nmAppReply("appState", "active");
	runApp((): NeonNode => <View />);
	nmAppLogClear();
}

function requestId(log: string, command: string): string {
	const at = log.lastIndexOf(command + "(");
	const start = at + command.length + 1;
	return log.substring(start, log.indexOf(FIELD, start));
}

function asset(uri: string, width: string, height: string, type: string, size: string): string {
	return [uri, width, height, type, "photo.jpg", size, "image/jpeg", "", ""].join(FIELD);
}

test "the library picker sends the options, waits for the reply event and decodes the assets" {
	mount();
	nmAppReply("capture.pick", "");
	const pending = ImagePicker.launchImageLibraryAsync({ mediaTypes: ["images", "videos"], quality: 0.5, allowsMultipleSelection: true });
	await sleepAsync(5);
	const asked: string = nmAppLog();
	const id = requestId(asked, "capture.pick");
	assert asked.endsWith("capture.pick(" + id + FIELD + ["0", "1", "1", "0", "0.5", "0", "1", "0", "back"].join(FIELD) + ")"), asked;
	nmAppEvent(REPLY, id + FIELD + "ok" + RECORD + asset("file:///cache/a.jpg", "4032", "3024", "image", "1234567") + RECORD +
		["file:///cache/b.mp4", "1920", "1080", "video", "", "", "video/mp4", "3000", ""].join(FIELD));
	const picked: ImagePickerResult = await pending;
	assert !picked.canceled && picked.assets.length === 2, `${picked.canceled} ${picked.assets.length}`;
	const first = picked.assets[0];
	assert first.uri === "file:///cache/a.jpg" && first.width === 4032 && first.height === 3024 && first.type === "image", first.uri;
	assert first.fileSize === 1234567 && first.fileName === "photo.jpg" && first.base64 === null && first.duration === null, "fields";
	const second = picked.assets[1];
	assert second.type === "video" && second.duration === 3000 && second.fileSize === null && second.fileName === null, second.uri;
	nmTeardown();
}

test "a canceled pick has no assets and a host refusal throws its message" {
	mount();
	nmAppReply("capture.pick", "canceled");
	const canceled = await ImagePicker.launchImageLibraryAsync();
	assert canceled.canceled && canceled.assets.length === 0, "canceled";
	nmAppReply("capture.pick", "!ImagePicker: another picker is already open");
	let message = "";
	try {
		await ImagePicker.launchImageLibraryAsync();
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "ImagePicker: another picker is already open", message;
	nmTeardown();
}

test "the camera picker needs the camera permission before it opens" {
	mount();
	nmAppReply("permission.check", "denied" + FIELD + "1");
	let message = "";
	try {
		await ImagePicker.launchCameraAsync();
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "ImagePicker.launchCameraAsync: Missing camera permission", message;
	const before: string = nmAppLog();
	assert before.indexOf("capture.pick") < 0, "the picker never opened";
	nmAppReply("permission.check", "granted" + FIELD + "0");
	nmAppReply("capture.pick", "ok" + RECORD + asset("file:///cache/c.jpg", "640", "480", "image", "2048"));
	const shot = await ImagePicker.launchCameraAsync({ cameraType: "front", base64: true });
	assert shot.assets[0].uri === "file:///cache/c.jpg", shot.assets[0].uri;
	const log: string = nmAppLog();
	assert log.endsWith(FIELD + ["1", "1", "0", "0", "1", "1", "0", "0", "front"].join(FIELD) + ")"), log;
	nmTeardown();
}

function status(loaded: boolean, playing: boolean, position: string, finished: boolean): string {
	return [loaded ? "1" : "0", playing ? "1" : "0", "0", position, "3000", finished ? "1" : "0", "0", "1", "0", "1", ""].join(FIELD);
}

test "a Sound loads through the reply event, plays by command and reports status events until it finishes" {
	mount();
	const seen: string[] = [];
	nmAppReply("sound.load", "");
	const created = Audio.Sound.createAsync({ uri: "file:///clip.wav" }, { volume: 0.5 }, (s: AVPlaybackStatus): void => {
		seen.push(`${s.isPlaying ? "playing" : "idle"}@${s.positionMillis}${s.didJustFinish ? " finished" : ""}`);
	});
	await sleepAsync(5);
	const asked: string = nmAppLog();
	const id = requestId(asked, "sound.load");
	assert asked.indexOf(FIELD + "file:///clip.wav" + FIELD + "0" + FIELD + "0.5" + FIELD) > 0, asked;
	nmAppEvent(REPLY, id + FIELD + status(true, false, "0", false));
	const made = await created;
	const sound: Sound = made.sound;
	assert made.status.isLoaded && made.status.durationMillis === 3000 && made.status.uri === "file:///clip.wav", "loaded";
	const soundId = asked.substring(asked.indexOf(FIELD, asked.lastIndexOf("sound.load(")) + 1, asked.length).split(FIELD)[0];
	nmAppReply("sound.play", status(true, true, "0", false));
	const playing = await sound.playAsync();
	assert playing.isPlaying && playing.shouldPlay, "playing";
	nmAppEvent(SOUND, soundId + FIELD + status(true, true, "1500", false));
	nmAppEvent(SOUND, soundId + FIELD + status(true, false, "3000", true));
	nmAppReply("sound.seek", status(true, false, "1000", false));
	await sound.setPositionAsync(1000);
	nmAppReply("sound.unload", status(false, false, "0", false));
	await sound.unloadAsync();
	assert seen.join(",") === "idle@0,playing@0,playing@1500,idle@3000 finished,idle@1000,idle@0", seen.join(",");
	const log: string = nmAppLog();
	assert log.indexOf("sound.play(" + soundId + FIELD + "0)") > 0 && log.indexOf("sound.seek(" + soundId + FIELD + "1000)") > 0, log;
	let message = "";
	try {
		await sound.playAsync();
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Cannot complete operation because sound is not loaded.", message;
	nmTeardown();
}

test "a Sound that fails to load rejects with the host's error" {
	mount();
	nmAppReply("sound.load", "!Sound.loadAsync: cannot open file:///missing.wav");
	let message = "";
	try {
		await Audio.Sound.createAsync({ uri: "file:///missing.wav" });
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Sound.loadAsync: cannot open file:///missing.wav", message;
	nmTeardown();
}

function recordingState(recording: boolean, done: boolean, duration: string, uri: string): string {
	return ["1", recording ? "1" : "0", done ? "1" : "0", duration, uri, ""].join(FIELD);
}

test "a Recording asks for the microphone, records by command and gives back a uri a Sound can load" {
	mount();
	nmAppReply("permission.check", "undetermined" + FIELD + "1");
	let message = "";
	try {
		await Audio.Recording.createAsync();
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Missing audio recording permissions.", message;
	nmAppReply("permission.check", "granted" + FIELD + "0");
	nmAppReply("audio.mode", "");
	await Audio.setAudioModeAsync({ allowsRecordingIOS: true, playsInSilentModeIOS: true });
	nmAppReply("recording.prepare", recordingState(false, false, "0", "file:///cache/rec.m4a"));
	nmAppReply("recording.start", recordingState(true, false, "0", "file:///cache/rec.m4a"));
	const updates: string[] = [];
	const made = await Audio.Recording.createAsync(Audio.RecordingOptionsPresets.LOW_QUALITY, (s: RecordingStatus): void => {
		updates.push(`${s.isRecording ? "rec" : "idle"}@${s.durationMillis}`);
	});
	const recording: Recording = made.recording;
	assert made.status.isRecording && recording.getURI() === "file:///cache/rec.m4a", "recording";
	const log: string = nmAppLog();
	assert log.indexOf("audio.mode(1" + FIELD + "1)") >= 0, log;
	assert log.indexOf(FIELD + ".m4a" + FIELD + "44100" + FIELD + "1" + FIELD + "64000" + FIELD + "500)") > 0, log;
	const recId = log.substring(log.indexOf("recording.start(") + 16, log.length).split(FIELD)[0];
	nmAppEvent(RECORDING, recId + FIELD + recordingState(true, false, "500", "file:///cache/rec.m4a"));
	nmAppReply("recording.stop", recordingState(false, true, "1200", "file:///cache/rec.m4a"));
	const stopped = await recording.stopAndUnloadAsync();
	assert stopped.isDoneRecording && stopped.durationMillis === 1200 && stopped.uri === "file:///cache/rec.m4a", "stopped";
	assert updates.join(",") === "idle@0,rec@0,rec@500,idle@1200", updates.join(",");
	nmAppReply("sound.load", status(true, false, "0", false));
	const playback = await recording.createNewLoadedSoundAsync();
	assert playback.status.isLoaded && playback.status.uri === "file:///cache/rec.m4a", playback.status.uri;
	nmTeardown();
}

// A test body awaiting a rejected promise segfaults on C (compiler card
// 2026-10-08-test-block-awaiting-a-rejected-nullable-promise-segfaults.md); an async helper does not.
async function rejection(pending: Promise<CameraCapturedPicture>): Promise<string> {
	try {
		await pending;
	} catch (e) {
		return (e as Error).message;
	}
	return "resolved";
}

test "a native CameraView is a media view: facing and flash props, ready and mount errors, takePictureAsync by command" {
	const [facing, setFacing] = createSignal("back");
	let log = "";
	let handle: CameraViewHandle | null = null;
	const app = (): NeonNode => <View style={{ width: 300 }}>
		<CameraView
			facing={facing() as CameraType}
			flash="auto"
			style={{ width: 300, height: 400 }}
			ref={(h: CameraViewHandle): void => { handle = h; }}
			onCameraReady={(): void => { log += "ready;"; }}
			onMountError={(e: CameraMountError): void => { log += `error ${e.message};`; }}
		/>
	</View>;
	runApp(app);
	const camera = nmLastControlTag(CAMERA);
	assert `${nmLayoutWidth(camera)}x${nmLayoutHeight(camera)}` === "300x400", `${nmLayoutWidth(camera)}x${nmLayoutHeight(camera)}`;
	assert prop(camera, "facing") === "back" && prop(camera, "flash") === "auto" && prop(camera, "active") === "true", "props";
	setFacing("front");
	assert prop(camera, "facing") === "front", "facing follows its signal";
	nmControl(camera, 30, "");
	nmControl(camera, 31, "Camera permission not granted");
	assert log === "ready;error Camera permission not granted;", log;
	const h = handle as CameraViewHandle;
	const pending = h.takePictureAsync({ quality: 0.7 });
	const command = prop(camera, "command");
	assert command.startsWith("takePicture" + FIELD) && command.endsWith(FIELD + "0.7" + FIELD + "0"), command;
	const id = command.split(FIELD)[1];
	nmControl(camera, 32, id + FIELD + "ok" + FIELD + "file:///cache/shot.jpg" + FIELD + "1080" + FIELD + "1920" + FIELD + "");
	const picture: CameraCapturedPicture = await pending;
	assert picture.uri === "file:///cache/shot.jpg" && picture.width === 1080 && picture.height === 1920 && picture.base64 === null, picture.uri;
	const failing = h.takePictureAsync();
	const second = (prop(camera, "command") as string).split(FIELD)[1];
	nmControl(camera, 32, second + FIELD + "error" + FIELD + "no camera available");
	const message = await rejection(failing);
	assert message === "CameraView.takePictureAsync: no camera available", message;
	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "camera views are released";
}
