// Modals in an Ion window: each fills the root above the app, takes the pointer, and closes on Escape from the topmost.
//   msc build examples/windowsNative/ionModal.ms --output=out/windowsIonModal.exe
//   out/windowsIonModal.exe            opens the window and toggles a Modal every two seconds, logging each request to close it
//   out/windowsIonModal.exe --check    shows and hides two Modals, presses through them, sends Escape through posted key messages,
//                                      and exits 0 when every expectation holds

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/windows/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Pressable } from "../../src/components/primitives";
import { Modal } from "../../src/components/modal";
import { harnessIsCheck, harnessExpect, harnessSample, harnessPostKeys } from "./harness.h";
import { niwPointer } from "../../src/platform/windows/handoff.h";
import { exit } from "std/process";

when (windows) {
	@compile("./harness.cpp");
	@passL("-ld3d11");
	@passL("-ld2d1");
	@passL("-ldcomp");
	@passL("-ldwmapi");
	@passL("-lgdi32");
	@passL("-ldwrite");
}

const styles = createStyles({
	base: { width: 480, height: 320, backgroundColor: "#101820" },
	under: { position: "absolute", left: 20, top: 20, width: 200, height: 100, backgroundColor: "#e63a3a" },
	first: { position: "absolute", left: 40, top: 180, width: 100, height: 100, backgroundColor: "#2ecc71" },
	second: { position: "absolute", left: 300, top: 180, width: 100, height: 100, backgroundColor: "#f1c40f" },
});

const [showFirst, setShowFirst] = createSignal(false);
const [showSecond, setShowSecond] = createSignal(false);
let presses = 0;
let shown = 0;
let dismissed = 0;
const closes: string[] = [];

function requestClose(name: string): () => void {
	return (): void => {
		closes.push(name);
		console.log(`close requested by ${name}`);
	};
}

function App(): NeonNode {
	return <View style={styles.base}>
		<Pressable style={styles.under} onPress={(e: NeonEvent): void => { presses += 1; console.log(`press under ${presses}`); }} />
		<Modal visible={showFirst()} animationType="fade" onRequestClose={requestClose("first")}
			onShow={(): void => { shown += 1; }} onDismiss={(): void => { dismissed += 1; }}>
			<View style={styles.first} />
		</Modal>
		<Modal visible={showSecond()} animationType="slide" transparent={true} onRequestClose={requestClose("second")}>
			<View style={styles.second} />
		</Modal>
	</View>;
}

const TITLE = "Neon modal on Ion";
const check = harnessIsCheck() !== 0;
let failures = 0;

function expect(what: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "ok  " : "FAIL"} ${what}: ${detail}`);
	if (!ok) { failures += 1; }
}

function click(x: number, y: number): void {
	niwPointer(0, x as float32, y as float32);
	niwPointer(1, x as float32, y as float32);
}

function pixels(): void {
	failures += harnessSample(TITLE);
}

const steps: (() => void)[] = [];

function run(at: number): void {
	if (at >= steps.length) {
		console.log(`failures ${failures}`);
		exit(failures);
		return;
	}
	steps[at]();
	setTimeout((): void => { run(at + 1); }, 700);
}

steps.push((): void => {
	harnessExpect("app visible", 30, 30, 230, 58, 58);
	pixels();
	click(30.0, 30.0);
	expect("press reaches the app with no Modal", presses === 1, `${presses}`);
	setShowFirst(true);
});
steps.push((): void => {
	harnessExpect("first Modal paints over the pressable", 30, 30, 0, 0, 0);
	harnessExpect("first Modal content", 90, 230, 46, 204, 113);
	pixels();
	expect("onShow ran once", shown === 1, `${shown}`);
	click(30.0, 30.0);
	expect("press on the Modal does not reach the app beneath", presses === 1, `${presses}`);
	setShowFirst(false);
});
steps.push((): void => {
	harnessExpect("hidden Modal uncovers the app", 30, 30, 230, 58, 58);
	harnessExpect("hidden Modal content gone", 90, 230, 16, 24, 32);
	pixels();
	expect("onDismiss ran once", dismissed === 1, `${dismissed}`);
	click(30.0, 30.0);
	expect("press reaches the app again", presses === 2, `${presses}`);
	setShowFirst(true);
	setShowSecond(true);
});
steps.push((): void => {
	harnessExpect("second Modal content", 350, 230, 241, 196, 15);
	harnessExpect("first Modal still under the second", 90, 230, 46, 204, 113);
	harnessExpect("transparent second Modal leaves the first beneath", 30, 30, 0, 0, 0);
	pixels();
	harnessPostKeys(TITLE, "\u001b");
});
steps.push((): void => {
	expect("Escape asks only the topmost Modal to close", closes.join(",") === "second", closes.join(","));
	setShowSecond(false);
});
steps.push((): void => {
	harnessExpect("second Modal gone", 350, 230, 0, 0, 0);
	pixels();
	harnessPostKeys(TITLE, "\u001b");
});
steps.push((): void => {
	expect("with the second gone the first is topmost", closes.join(",") === "second,first", closes.join(","));
	expect("Escape reached no press", presses === 2, `${presses}`);
});

function toggleForever(): void {
	setShowFirst(!showFirst());
	setTimeout(toggleForever, 2000);
}

const options = nativeWindowOptions(TITLE, 480, 320);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (): void => {
	setTimeout((): void => { run(0); }, 700);
} : (): void => { setTimeout(toggleForever, 1000); }));
