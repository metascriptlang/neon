import { createSignal } from "../../src/core/signal";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { Show } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { View, Text, Pressable } from "../../src/components/primitives";
import { Image } from "../../src/components/image";
import { ImagePicker, ImagePickerResult } from "../../src/api/imagePicker";
import { Audio, AVPlaybackStatus, Recording, RecordingStatus, Sound } from "../../src/api/audio";
import { Camera, CameraType, CameraView, CameraViewHandle, CameraMountError } from "../../src/components/cameraView";
import { CHIME_WAV } from "./clip";

const styles = createStyles({
	screen: { flex: 1, backgroundColor: "#11111b" },
	top: { paddingTop: 48, paddingLeft: 12, paddingRight: 12, paddingBottom: 8, gap: 6, backgroundColor: "#1e1e2e" },
	title: { color: "#cdd6f4", fontSize: 20, fontWeight: "bold" },
	status: { color: "#89b4fa", fontSize: 15 },
	row: { flexDirection: "row", flexWrap: "wrap", gap: 6 },
	tab: { paddingTop: 8, paddingBottom: 8, paddingLeft: 10, paddingRight: 10, backgroundColor: "#45475a", color: "#cdd6f4", borderRadius: 6 },
	button: { paddingTop: 8, paddingBottom: 8, paddingLeft: 12, paddingRight: 12, backgroundColor: "#89b4fa", color: "#11111b", borderRadius: 6 },
	body: { flex: 1, padding: 8, gap: 8 },
	photo: { width: 240, height: 180, alignSelf: "center", backgroundColor: "#313244" },
	camera: { width: 300, height: 300, alignSelf: "center" },
	note: { color: "#a6adc8", fontSize: 13 },
});

interface ScreenProps {
	say: (s: string) => void;
}

function size(width: number, height: number): string {
	return `${Math.round(width)}x${Math.round(height)}`;
}

function errorText(e: Error): string {
	return e.message;
}

// The async handlers live in classes: on JS a function declaring a nested async function is itself
// emitted async (compiler card 2026-10-07-js-outer-function-made-async-by-nested-async.md).
class PickActions {
	say: (s: string) => void;
	setPhoto: (uri: string) => void;

	constructor(say: (s: string) => void, setPhoto: (uri: string) => void) {
		this.say = say;
		this.setPhoto = setPhoto;
	}

	show(result: ImagePickerResult, what: string): void {
		if (result.canceled) {
			this.say(what + " canceled");
			return;
		}
		const asset = result.assets[0];
		this.setPhoto(asset.uri);
		this.say(`${what} ${asset.type} ${size(asset.width, asset.height)}`);
	}

	async pick(): Promise<void> {
		try {
			this.show(await ImagePicker.launchImageLibraryAsync({ quality: 0.8 }), "picked");
		} catch (e) {
			this.say("pick error " + errorText(e as Error));
		}
	}

	async shoot(): Promise<void> {
		try {
			const permission = await ImagePicker.requestCameraPermissionsAsync();
			if (!permission.granted) {
				this.say("camera permission " + permission.status);
				return;
			}
			this.show(await ImagePicker.launchCameraAsync({ quality: 0.8 }), "shot");
		} catch (e) {
			this.say("camera error " + errorText(e as Error));
		}
	}
}

function PickScreen(props: ScreenProps): NeonNode {
	const [photo, setPhoto] = createSignal("");
	const actions = new PickActions(props.say, (uri: string): void => { setPhoto(uri); });
	return <View style={styles.body}>
		<View style={styles.row}>
			<Pressable style={styles.button} onPress={() => { actions.pick(); }}>pick photo</Pressable>
			<Pressable style={styles.button} onPress={() => { actions.shoot(); }}>system camera</Pressable>
		</View>
		<Show when={photo() !== ""}>
			<Image style={styles.photo} source={{ uri: photo() }} resizeMode="contain" />
		</Show>
	</View>;
}

class CameraActions {
	say: (s: string) => void;
	setOpen: (open: boolean) => void;
	setPicture: (uri: string) => void;
	camera: CameraViewHandle | null = null;

	constructor(say: (s: string) => void, setOpen: (open: boolean) => void, setPicture: (uri: string) => void) {
		this.say = say;
		this.setOpen = setOpen;
		this.setPicture = setPicture;
	}

	async start(): Promise<void> {
		const permission = await Camera.requestCameraPermissionsAsync();
		this.say("camera permission " + permission.status);
		if (permission.granted) { this.setOpen(true); }
	}

	async take(): Promise<void> {
		const camera = this.camera;
		if (camera === null) {
			this.say("picture error the camera is closed");
			return;
		}
		try {
			const shot = await (camera as CameraViewHandle).takePictureAsync({ quality: 0.7 });
			this.setPicture(shot.uri);
			this.say("picture " + size(shot.width, shot.height));
		} catch (e) {
			this.say("picture error " + errorText(e as Error));
		}
	}
}

function CameraScreen(props: ScreenProps): NeonNode {
	const say = props.say;
	const [open, setOpen] = createSignal(false);
	const [facing, setFacing] = createSignal("back");
	const [picture, setPicture] = createSignal("");
	const actions = new CameraActions(say, (value: boolean): void => { setOpen(value); }, (uri: string): void => { setPicture(uri); });
	return <View style={styles.body}>
		<View style={styles.row}>
			<Pressable style={styles.button} onPress={() => { actions.start(); }}>open camera</Pressable>
			<Pressable style={styles.button} onPress={() => { actions.take(); }}>take picture</Pressable>
			<Pressable style={styles.button} onPress={() => { setFacing(facing() === "back" ? "front" : "back"); }}>flip</Pressable>
			<Pressable style={styles.button} onPress={() => {
				setOpen(false);
				actions.camera = null;
				say("camera closed");
			}}>close</Pressable>
		</View>
		<Show when={open()}>
			<CameraView
				style={styles.camera}
				facing={facing() as CameraType}
				ref={(h: CameraViewHandle): void => { actions.camera = h; }}
				onCameraReady={(): void => { say("camera ready " + facing()); }}
				onMountError={(e: CameraMountError): void => { say("camera error " + e.message); }}
			/>
		</Show>
		<Show when={picture() !== ""}>
			<Image style={styles.photo} source={{ uri: picture() }} resizeMode="contain" />
		</Show>
	</View>;
}

class AudioActions {
	say: (s: string) => void;
	setPosition: (text: string) => void;
	chime: Sound | null = null;
	recording: Recording | null = null;
	playback: Sound | null = null;

	constructor(say: (s: string) => void, setPosition: (text: string) => void) {
		this.say = say;
		this.setPosition = setPosition;
	}

	follow(what: string, s: AVPlaybackStatus): void {
		this.setPosition(Math.round(s.positionMillis).toString());
		if (s.didJustFinish) { this.say(what + " finished"); }
	}

	async play(): Promise<void> {
		try {
			if (this.chime === null) {
				await Audio.setAudioModeAsync({ playsInSilentModeIOS: true });
				const made = await Audio.Sound.createAsync({ uri: CHIME_WAV }, { progressUpdateIntervalMillis: 100 },
					(s: AVPlaybackStatus): void => { this.follow("clip", s); });
				this.chime = made.sound;
				this.say("clip loaded " + Math.round(made.status.durationMillis).toString() + "ms");
			}
			await (this.chime as Sound).replayAsync();
			this.say("clip playing");
		} catch (e) {
			this.say("clip error " + errorText(e as Error));
		}
	}

	async record(): Promise<void> {
		try {
			const permission = await Audio.requestPermissionsAsync();
			if (!permission.granted) {
				this.say("microphone permission " + permission.status);
				return;
			}
			await Audio.setAudioModeAsync({ allowsRecordingIOS: true, playsInSilentModeIOS: true });
			const made = await Audio.Recording.createAsync(Audio.RecordingOptionsPresets.HIGH_QUALITY, (s: RecordingStatus): void => {
				if (s.isRecording) { this.setPosition(Math.round(s.durationMillis).toString()); }
			}, 200);
			this.recording = made.recording;
			this.say("recording");
		} catch (e) {
			this.say("record error " + errorText(e as Error));
		}
	}

	async stop(): Promise<void> {
		const recording = this.recording;
		if (recording === null) {
			this.say("stop error nothing is recording");
			return;
		}
		try {
			const stopped = await (recording as Recording).stopAndUnloadAsync();
			this.say("recorded " + (stopped.durationMillis >= 500 ? "500+" : "<500") + "ms");
		} catch (e) {
			this.say("stop error " + errorText(e as Error));
		}
	}

	async replay(): Promise<void> {
		const recording = this.recording;
		if (recording === null) {
			this.say("playback error nothing was recorded");
			return;
		}
		try {
			await Audio.setAudioModeAsync({ allowsRecordingIOS: false, playsInSilentModeIOS: true });
			const made = await (recording as Recording).createNewLoadedSoundAsync({ shouldPlay: true },
				(s: AVPlaybackStatus): void => { this.follow("recording", s); });
			this.playback = made.sound;
			this.say("recording playing");
		} catch (e) {
			this.say("playback error " + errorText(e as Error));
		}
	}
}

function AudioScreen(props: ScreenProps): NeonNode {
	const [position, setPosition] = createSignal("0");
	const actions = new AudioActions(props.say, (text: string): void => { setPosition(text); });
	return <View style={styles.body}>
		<View style={styles.row}>
			<Pressable style={styles.button} onPress={() => { actions.play(); }}>play clip</Pressable>
			<Pressable style={styles.button} onPress={() => { actions.record(); }}>record</Pressable>
			<Pressable style={styles.button} onPress={() => { actions.stop(); }}>stop</Pressable>
			<Pressable style={styles.button} onPress={() => { actions.replay(); }}>play recording</Pressable>
		</View>
		<Text style={styles.status}>{"at " + position() + "ms"}</Text>
	</View>;
}

export function CaptureApp(): NeonNode {
	const [screen, setScreen] = createSignal<int32>(0);
	const [status, setStatus] = createSignal("ready");
	const say = (s: string): void => { setStatus(s); };
	return <View style={styles.screen}>
		<View style={styles.top}>
			<Text style={styles.title}>Neon capture</Text>
			<Text style={styles.status}>{"status " + status()}</Text>
			<View style={styles.row}>
				<Pressable style={styles.tab} onPress={() => { setScreen(0); say("photos"); }}>photos</Pressable>
				<Pressable style={styles.tab} onPress={() => { setScreen(1); say("camera"); }}>camera</Pressable>
				<Pressable style={styles.tab} onPress={() => { setScreen(2); say("audio"); }}>audio</Pressable>
			</View>
		</View>
		<Show when={screen() === 0}><PickScreen say={say} /></Show>
		<Show when={screen() === 1}><CameraScreen say={say} /></Show>
		<Show when={screen() === 2}><AudioScreen say={say} /></Show>
	</View>;
}
