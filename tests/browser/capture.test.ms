// chrome-args: --use-fake-device-for-media-stream --use-fake-ui-for-media-stream --autoplay-policy=no-user-gesture-required
import { domHost, documentBody } from "../../src/platform/browser/dom";
import { render } from "../../src/render/host";
import { View } from "../../src/components/primitives";
import { ImagePicker, ImagePickerResult } from "../../src/api/imagePicker";
import { Audio, AVPlaybackStatus, Sound } from "../../src/api/audio";
import { CameraView, CameraViewHandle, CameraCapturedPicture, CameraMountError } from "../../src/components/cameraView";
import { CHIME_WAV } from "../../examples/capture/clip";
import { sleepAsync } from "std/core/promise";

extern function js(code: cstring): string from "String((0, eval)(#))";

async function waitFor(what: string, ready: () => boolean, ms: number): Promise<void> {
	const end = performance.now() + ms;
	while (!ready()) {
		if (performance.now() > end) { throw new Error("timed out waiting for " + what); }
		await sleepAsync(20);
	}
}

const CHOOSE_PNG = "(() => { const c = document.createElement('canvas'); c.width = 64; c.height = 48; const g = c.getContext('2d');" +
	" g.fillStyle = '#ff0000'; g.fillRect(0, 0, 64, 48); const bytes = atob(c.toDataURL('image/png').split(',')[1]);" +
	" const a = new Uint8Array(bytes.length); for (let i = 0; i < bytes.length; i++) a[i] = bytes.charCodeAt(i);" +
	" const input = document.querySelector('input[data-neon-picker]'); const t = new DataTransfer();" +
	" t.items.add(new File([a], 'red.png', { type: 'image/png' })); input.files = t.files;" +
	" input.dispatchEvent(new Event('change')); return input.accept + '|' + input.multiple; })()";

// Headless Chrome on macOS never settles getUserMedia({ audio }) even with the fake device (measured
// 2026-10-08, Chrome stable), so the recording test records a Web Audio oscillator through the same API.
const SYNTHETIC_MICROPHONE = "(() => { const real = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);" +
	" navigator.mediaDevices.getUserMedia = (c) => { if (c && c.audio && !c.video) { const ctx = new AudioContext();" +
	" const o = ctx.createOscillator(); const d = ctx.createMediaStreamDestination(); o.connect(d); o.start();" +
	" return Promise.resolve(d.stream); } return real(c); }; return 'stubbed'; })()";

test "the library picker is a file input: a chosen png becomes an asset with its size, name and base64" {
	domHost();
	let result: ImagePickerResult | null = null;
	ImagePicker.launchImageLibraryAsync({ base64: true }).then((r: ImagePickerResult): void => { result = r; });
	await waitFor("the file input", (): boolean => js("String(!!document.querySelector('input[data-neon-picker]'))") === "true", 2000);
	const input = js(CHOOSE_PNG);
	assert input === "image/*|false", input;
	await waitFor("the pick", (): boolean => result !== null, 5000);
	const picked = result as ImagePickerResult;
	assert !picked.canceled && picked.assets.length === 1, "one asset";
	const asset = picked.assets[0];
	assert asset.uri.startsWith("blob:") && asset.width === 64 && asset.height === 48 && asset.type === "image", `${asset.uri} ${asset.width}x${asset.height}`;
	assert asset.fileName === "red.png" && asset.mimeType === "image/png" && (asset.fileSize as number) > 0, asset.fileName as string;
	assert (asset.base64 as string).length > 100, "base64 of the image";
	assert js("String(document.querySelectorAll('input[data-neon-picker]').length)") === "0", "the input is removed";
}

test "a canceled file input answers canceled, and a camera pick asks the input to capture" {
	let result: ImagePickerResult | null = null;
	ImagePicker.launchImageLibraryAsync({ mediaTypes: ["images", "videos"], allowsMultipleSelection: true }).then((r: ImagePickerResult): void => { result = r; });
	await waitFor("the file input", (): boolean => js("String(!!document.querySelector('input[data-neon-picker]'))") === "true", 2000);
	assert js("(() => { const i = document.querySelector('input[data-neon-picker]'); return i.accept + '|' + i.multiple; })()") === "image/*,video/*|true", "accept";
	js("document.querySelector('input[data-neon-picker]').dispatchEvent(new Event('cancel'))");
	await waitFor("the cancel", (): boolean => result !== null, 2000);
	assert (result as ImagePickerResult).canceled && (result as ImagePickerResult).assets.length === 0, "canceled";
	await Audio.requestPermissionsAsync();
	const camera = await ImagePicker.requestCameraPermissionsAsync();
	assert camera.granted, "the fake media UI grants the camera";
	let shot: ImagePickerResult | null = null;
	ImagePicker.launchCameraAsync({ cameraType: "front" }).then((r: ImagePickerResult): void => { shot = r; });
	await waitFor("the camera input", (): boolean => js("String(!!document.querySelector('input[data-neon-picker]'))") === "true", 2000);
	assert js("document.querySelector('input[data-neon-picker]').getAttribute('capture')") === "user", "front camera capture";
	js("document.querySelector('input[data-neon-picker]').dispatchEvent(new Event('cancel'))");
	await waitFor("the camera cancel", (): boolean => shot !== null, 2000);
}

test "a CameraView streams the fake camera into a <video> and takes a jpeg picture" {
	let ready = 0;
	let failure = "";
	let handle: CameraViewHandle | null = null;
	render(<View>
		<CameraView
			style={{ width: 320, height: 240 }}
			ref={(h: CameraViewHandle): void => { handle = h; }}
			onCameraReady={(): void => { ready += 1; }}
			onMountError={(e: CameraMountError): void => { failure = e.message; }}
		/>
	</View>, domHost(), documentBody());
	await waitFor("the camera", (): boolean => ready > 0 || failure !== "", 8000);
	assert failure === "" && ready === 1, "ready: " + failure;
	assert js("String(document.querySelector('video.neon-camera').videoWidth > 0)") === "true", "the stream plays";
	let picture: CameraCapturedPicture | null = null;
	(handle as CameraViewHandle).takePictureAsync({ quality: 0.5, base64: true }).then((p: CameraCapturedPicture): void => { picture = p; });
	await waitFor("the picture", (): boolean => picture !== null, 5000);
	const shot = picture as CameraCapturedPicture;
	assert shot.uri.startsWith("data:image/jpeg;base64,") && shot.width > 0 && shot.height > 0, `${shot.width}x${shot.height}`;
	assert (shot.base64 as string).length > 100 && shot.uri.endsWith(shot.base64 as string), "base64 is the uri's payload";
}

test "a Sound plays the bundled chime to its end, and a Recording records the fake microphone into a playable blob" {
	const seen: AVPlaybackStatus[] = [];
	const made = await Audio.Sound.createAsync({ uri: CHIME_WAV }, { progressUpdateIntervalMillis: 50 },
		(s: AVPlaybackStatus): void => { seen.push(s); });
	assert made.status.isLoaded && Math.abs(made.status.durationMillis - 800) < 20, `duration ${made.status.durationMillis}`;
	const sound: Sound = made.sound;
	await sound.playAsync();
	await waitFor("the chime's end", (): boolean => seen.length > 0 && seen[seen.length - 1].didJustFinish, 5000);
	const last = seen[seen.length - 1];
	assert !last.isPlaying && Math.abs(last.positionMillis - 800) < 20, `${last.positionMillis}`;
	let progressed = false;
	for (const s of seen) { if (s.isPlaying && s.positionMillis > 100 && s.positionMillis < 750) { progressed = true; } }
	assert progressed, "progress while playing";
	await sound.unloadAsync();
	assert js(SYNTHETIC_MICROPHONE) === "stubbed", "microphone stub";
	const permission = await Audio.requestPermissionsAsync();
	assert permission.granted, "microphone";
	const recorded = await Audio.Recording.createAsync();
	await sleepAsync(700);
	const stopped = await recorded.recording.stopAndUnloadAsync();
	assert stopped.isDoneRecording && stopped.durationMillis >= 600 && (stopped.uri as string).startsWith("blob:"), `${stopped.durationMillis} ${stopped.uri}`;
	const playback = await recorded.recording.createNewLoadedSoundAsync();
	assert playback.status.isLoaded, "the recording loads as a Sound";
	await playback.sound.unloadAsync();
}
