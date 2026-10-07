import {
	CaptureServices, PickReply, PickRequest, RecordingSetup, RecordingState, SoundSetup, SoundState, installCaptureServices,
	unloadedSound,
} from "../../src/api/captureServices";
import { ImagePicker } from "../../src/api/imagePicker";
import { Audio, AVPlaybackStatus, Recording, RecordingStatus, Sound } from "../../src/api/audio";
import { decodePicture } from "../../src/components/cameraView";
import { FakeServices } from "./fakeServices";

class FakeCapture {
	log: string[] = [];
	request: PickRequest | null = null;
	reply: PickReply = { canceled: true, assets: [], error: "" };
	updates: ((state: SoundState) => void)[] = [];
	position: number = 0;
	playing: boolean = false;
	loop: boolean = false;
	volume: number = 1;
	loadError: string = "";
	recordingUpdate: ((state: RecordingState) => void) | null = null;
	recording: boolean = false;
	done: boolean = false;

	sound(): SoundState {
		const state = unloadedSound("");
		state.isLoaded = true;
		state.isPlaying = this.playing;
		state.positionMillis = this.position;
		state.durationMillis = 2000;
		state.isLooping = this.loop;
		state.volume = this.volume;
		return state;
	}

	recorded(): RecordingState {
		return {
			canRecord: !this.done,
			isRecording: this.recording,
			isDoneRecording: this.done,
			durationMillis: this.done ? 900 : 0,
			uri: "blob:recording",
			error: "",
		};
	}

	install(): void {
		const services: CaptureServices = {
			pickMedia: async (request: PickRequest): Promise<PickReply> => {
				this.request = request;
				return this.reply;
			},
			soundLoad: async (id: int32, setup: SoundSetup, update: (state: SoundState) => void): Promise<SoundState> => {
				this.log.push(`load ${setup.uri} play=${setup.shouldPlay} volume=${setup.volume} every=${setup.progressUpdateIntervalMillis}`);
				if (this.loadError !== "") { return unloadedSound(this.loadError); }
				this.updates.push(update);
				this.volume = setup.volume;
				this.playing = setup.shouldPlay;
				return this.sound();
			},
			soundCommand: (id: int32, command: string, value: number): SoundState => {
				this.log.push(`${command} ${value}`);
				if (command === "play") { this.playing = true; }
				if (command === "pause" || command === "stop") { this.playing = false; }
				if (command === "stop") { this.position = 0; }
				if (command === "seek") { this.position = value; }
				if (command === "loop") { this.loop = value === 1; }
				if (command === "volume") { this.volume = value; }
				if (command === "unload") { return unloadedSound(""); }
				return this.sound();
			},
			audioMode: async (allowsRecording: boolean, playsInSilentMode: boolean): Promise<string> => {
				this.log.push(`mode ${allowsRecording} ${playsInSilentMode}`);
				return "";
			},
			recordingPrepare: async (id: int32, setup: RecordingSetup, update: (state: RecordingState) => void): Promise<RecordingState> => {
				this.log.push(`prepare ${setup.extension} ${setup.sampleRate} ${setup.numberOfChannels} ${setup.bitRate}`);
				this.recordingUpdate = update;
				return this.recorded();
			},
			recordingCommand: async (id: int32, command: string, value: number): Promise<RecordingState> => {
				this.log.push(`recording ${command}`);
				if (command === "start") { this.recording = true; }
				if (command === "stop") {
					this.recording = false;
					this.done = true;
				}
				return this.recorded();
			},
		};
		installCaptureServices(services);
	}

	finish(): void {
		this.playing = false;
		this.position = 2000;
		const state = this.sound();
		state.didJustFinish = true;
		for (const update of this.updates) { update(state); }
	}
}

async function failure(run: () => Promise<void>): Promise<string> {
	try {
		await run();
	} catch (e) {
		return (e as Error).message;
	}
	return "none";
}

test "ImagePicker maps expo's options onto the pick request and the reply onto expo's result" {
	const capture = new FakeCapture();
	capture.install();
	capture.reply = {
		canceled: false,
		assets: [{
			uri: "file:///a.jpg", width: 10, height: 20, type: "image", fileName: "a.jpg", fileSize: 99, mimeType: "image/jpeg",
			duration: -1, base64: "QUJD",
		}],
		error: "",
	};
	const picked = await ImagePicker.launchImageLibraryAsync({
		mediaTypes: ["videos"], quality: 0.25, base64: true, allowsMultipleSelection: true, selectionLimit: 3,
	});
	const request = capture.request as PickRequest;
	assert !request.camera && !request.images && request.videos && request.quality === 0.25 && request.base64, "request";
	assert request.multiple && request.selectionLimit === 3 && request.cameraType === "back", "multiple";
	assert !picked.canceled && picked.assets.length === 1, "result";
	const asset = picked.assets[0];
	assert asset.uri === "file:///a.jpg" && asset.base64 === "QUJD" && asset.fileSize === 99 && asset.duration === null, asset.uri;
	assert asset.assetId === null && asset.mimeType === "image/jpeg", "absent fields are null";
	await ImagePicker.launchImageLibraryAsync();
	const defaults = capture.request as PickRequest;
	assert defaults.images && !defaults.videos && defaults.quality === 1 && !defaults.multiple, "defaults are images at full quality";
}

test "ImagePicker refuses a quality outside 0..1 and reports a host refusal" {
	const capture = new FakeCapture();
	capture.install();
	const quality = await failure(async (): Promise<void> => { await ImagePicker.launchImageLibraryAsync({ quality: 2 }); });
	assert quality === "ImagePicker: quality must be between 0 and 1, got 2", quality;
	capture.reply = { canceled: false, assets: [], error: "ImagePicker: another picker is already open" };
	const busy = await failure(async (): Promise<void> => { await ImagePicker.launchImageLibraryAsync(); });
	assert busy === "ImagePicker: another picker is already open", busy;
}

test "launchCameraAsync checks the camera permission through Permissions first" {
	const fake = new FakeServices();
	fake.install();
	const capture = new FakeCapture();
	capture.install();
	fake.answer = "denied";
	fake.permissionNames.push("camera");
	fake.permissionStates.push("denied");
	const refused = await failure(async (): Promise<void> => { await ImagePicker.launchCameraAsync(); });
	assert refused === "ImagePicker.launchCameraAsync: Missing camera permission", refused;
	assert capture.request === null, "the camera never opened";
}

test "a Sound reports every status change to its listener, including the one that finishes" {
	const capture = new FakeCapture();
	capture.install();
	const seen: string[] = [];
	const made = await Audio.Sound.createAsync({ uri: "https://neon.dev/a.mp3" }, { shouldPlay: true, volume: 0.5 },
		(s: AVPlaybackStatus): void => { seen.push(`${s.isPlaying}/${s.positionMillis}/${s.didJustFinish}`); });
	const sound: Sound = made.sound;
	assert made.status.isLoaded && made.status.isPlaying && made.status.shouldPlay && made.status.volume === 0.5, "loaded playing";
	capture.finish();
	await sound.setIsLoopingAsync(true);
	await sound.replayAsync();
	await sound.stopAsync();
	const status = await sound.getStatusAsync();
	assert !status.isPlaying && status.positionMillis === 0 && status.isLooping, "stopped";
	await sound.unloadAsync();
	assert !(await sound.getStatusAsync()).isLoaded, "unloaded";
	assert capture.log.join(";") === "load https://neon.dev/a.mp3 play=true volume=0.5 every=500;loop 1;seek 0;play 0;stop 0;status 0;unload 0", capture.log.join(";");
	assert seen.join(",") === "true/0/false,false/2000/true,false/2000/false,false/0/false,true/0/false,false/0/false,false/0/false", seen.join(",");
}

test "Sound refuses bad arguments and commands once unloaded, and a failed load throws the host's error" {
	const capture = new FakeCapture();
	capture.install();
	const sound = new Sound();
	const early = await failure(async (): Promise<void> => { await sound.playAsync(); });
	assert early === "Cannot complete operation because sound is not loaded.", early;
	const volume = await failure(async (): Promise<void> => { await sound.loadAsync({ uri: "file:///a.wav" }, { volume: 3 }); });
	assert volume === "Sound: volume must be between 0 and 1, got 3", volume;
	capture.loadError = "Sound.loadAsync: cannot load file:///missing.wav: not found";
	const missing = await failure(async (): Promise<void> => { await sound.loadAsync({ uri: "file:///missing.wav" }); });
	assert missing === "Sound.loadAsync: cannot load file:///missing.wav: not found", missing;
}

test "a Recording prepares with the preset, stops into a uri and loads it as a Sound" {
	const fake = new FakeServices();
	fake.install();
	const capture = new FakeCapture();
	capture.install();
	fake.permissionNames.push("microphone");
	fake.permissionStates.push("granted");
	await Audio.setAudioModeAsync({ allowsRecordingIOS: true });
	const recording = new Recording();
	await recording.prepareToRecordAsync(Audio.RecordingOptionsPresets.HIGH_QUALITY);
	assert recording.getURI() === "blob:recording", "the uri is known once prepared";
	const started = await recording.startAsync();
	assert started.isRecording && started.canRecord, "recording";
	const twice = await failure(async (): Promise<void> => { await recording.prepareToRecordAsync(); });
	assert twice === "This Recording object is already prepared to record.", twice;
	const stopped: RecordingStatus = await recording.stopAndUnloadAsync();
	assert stopped.isDoneRecording && stopped.durationMillis === 900 && stopped.uri === "blob:recording", "stopped";
	const again = await failure(async (): Promise<void> => { await recording.startAsync(); });
	assert again === "Cannot start a Recording that is done recording.", again;
	const playback = await recording.createNewLoadedSoundAsync();
	assert playback.status.uri === "blob:recording", playback.status.uri;
	assert capture.log.join(";") === "mode true false;prepare .m4a 44100 2 128000;recording start;recording stop;load blob:recording play=false volume=1 every=500", capture.log.join(";");
}

test "a camera picture reply decodes, and an error reply throws its message" {
	const picture = decodePicture("ok\x1fdata:image/jpeg;base64,QUJD\x1f640\x1f480\x1fQUJD");
	assert picture.uri.startsWith("data:image/jpeg") && picture.width === 640 && picture.height === 480 && picture.base64 === "QUJD", picture.uri;
	let message = "";
	try {
		decodePicture("error\x1fthe camera is not running");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "CameraView.takePictureAsync: the camera is not running", message;
}
