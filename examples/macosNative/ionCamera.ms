// CameraView in a macOS Ion window: an AVCaptureSession with its preview layer and a photo output.
//   msc build examples/macosNative/ionCamera.ms --output=out/macosIonCamera
//   out/macosIonCamera            asks for the camera permission, then mounts the CameraView and logs whether it became
//                                 ready or why it could not mount
//   out/macosIonCamera --check    mounts a CameraView without asking for permission: with the camera already authorized it
//                                 expects onCameraReady and a picture, without it onMountError naming the permission; the
//                                 permission Ion reads must agree with the branch taken; exits 0 when every expectation holds

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { View } from "../../src/components/primitives";
import { createSignal } from "../../src/core/signal";
import { Show } from "../../src/macros/ui/flow";
import { CameraView, CameraViewHandle, CameraMountError, Camera } from "../../src/components/cameraView";
import { harnessIsCheck } from "./harness.h";
import { exit } from "std/process";

when (macos) {
	@compile("./harness.m", "-fobjc-arc");
}

const styles = createStyles({
	base: { width: 480, height: 320, backgroundColor: "#101820" },
	camera: { position: "absolute", left: 20, top: 20, width: 320, height: 240 },
});

let readies = 0;
const mountErrors: string[] = [];
let handle: CameraViewHandle | null = null;
const check = harnessIsCheck() !== 0;
const [asked, setAsked] = createSignal(check);

function App(): NeonNode {
	return <View style={styles.base}>
		<Show when={asked()}>
			<CameraView style={styles.camera} facing="front"
				ref={(h: CameraViewHandle): void => { handle = h; }}
				onCameraReady={(): void => {
					readies += 1;
					console.log("camera ready");
				}}
				onMountError={(e: CameraMountError): void => {
					mountErrors.push(e.message);
					console.log(`mount error "${e.message}"`);
				}} />
		</Show>
	</View>;
}

const TITLE = "Neon camera on Ion";
let failures = 0;
let picture = "<none>";
let permissionCheck = "<none>";

function expect(what: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "ok  " : "FAIL"} ${what}: ${detail}`);
	if (!ok) { failures += 1; }
}

function camera(): CameraViewHandle {
	if (handle === null) { throw new Error("the CameraView ref never arrived"); }
	return handle as CameraViewHandle;
}

async function checkPermission(): Promise<void> {
	try {
		const got = await Camera.getCameraPermissionsAsync();
		permissionCheck = got.status;
	} catch (e) {
		permissionCheck = (e as Error).message;
	}
}

async function takePicture(): Promise<void> {
	try {
		const p = await camera().takePictureAsync({ quality: 0.5 });
		picture = `${p.uri.startsWith("file://") ? "file" : p.uri} ${p.width > 0 && p.height > 0 ? "sized" : "unsized"}`;
	} catch (e) {
		picture = (e as Error).message;
	}
}

// A step returns false while what it waits for has not arrived; run retries it every 100 ms, up to 3 s.
const steps: (() => boolean)[] = [];

function run(at: number, tries: number): void {
	if (at >= steps.length) {
		console.log(`failures ${failures}`);
		exit(failures);
		return;
	}
	if (!steps[at]() && tries < 30) {
		setTimeout((): void => { run(at, tries + 1); }, 100);
		return;
	}
	setTimeout((): void => { run(at + 1, 0); }, 700);
}

steps.push((): boolean => readies + mountErrors.length > 0);
steps.push((): boolean => {
	expect("the camera answers once, ready or refused", readies + mountErrors.length === 1, `${readies} ready, ${mountErrors.join(",")}`);
	console.log(`branch: ${readies > 0 ? "authorized, the session runs" : "not authorized, no prompt was shown"}`);
	checkPermission();
	if (readies > 0) {
		takePicture();
	} else {
		expect("a refused camera names the permission", mountErrors.length === 1 && mountErrors[0] === "Camera permission not granted", mountErrors.join(","));
	}
	return true;
});
steps.push((): boolean => permissionCheck !== "<none>" && (readies === 0 || picture !== "<none>"));
steps.push((): boolean => {
	expect("the camera permission Ion reads agrees with the branch", (permissionCheck === "granted") === (readies > 0) && (permissionCheck === "granted" || permissionCheck === "denied" || permissionCheck === "undetermined"), permissionCheck);
	if (readies > 0) {
		expect("a picture is taken to a file", picture === "file sized", picture);
	}
	return true;
});

const options = nativeWindowOptions(TITLE, 480, 320);
options.topmost = check;
async function askThenMount(): Promise<void> {
	const got = await Camera.requestCameraPermissionsAsync();
	console.log(`camera permission ${got.status}`);
	setAsked(true);
}

exit(runNativeWindow(options, App, check ? (): void => {
	setTimeout((): void => { run(0, 0); }, 1200);
} : (): void => { askThenMount(); }));
