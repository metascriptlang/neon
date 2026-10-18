// Modal in a macOS Ion window: a layer filling the window above the app, as on iOS; Escape asks the app to close it.
//   msc build examples/macosNative/ionModal.ms --output=out/macosIonModal
//   out/macosIonModal            opens the window; the green box opens the Modal, Escape or the red box closes it
//   out/macosIonModal --check    clicks and presses Escape through AppKit events, samples the window, and exits 0 when
//                                every expectation holds

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Pressable } from "../../src/components/primitives";
import { Modal } from "../../src/components/modal";
import { harnessIsCheck, harnessExpect, harnessSample, harnessClick, harnessPostKeys } from "./harness.h";
import { exit } from "std/process";

when (macos) {
	@compile("./harness.m", "-fobjc-arc");
}

const styles = createStyles({
	base: { width: 480, height: 320, backgroundColor: "#101820" },
	open: { position: "absolute", left: 20, top: 20, width: 100, height: 40, backgroundColor: "#27ae60" },
	under: { position: "absolute", left: 200, top: 20, width: 100, height: 40, backgroundColor: "#2e86de" },
	sheet: { position: "absolute", left: 190, top: 110, width: 100, height: 100, backgroundColor: "#e74c3c" },
});

const [visible, setVisible] = createSignal(false);
const [fade, setFade] = createSignal(true);
let opened = 0;
let unders = 0;
let closes = 0;
let shows = 0;
let dismissals = 0;

function App(): NeonNode {
	return <View style={styles.base}>
		<Pressable style={styles.open} onPress={(e: NeonEvent): void => {
			opened += 1;
			setVisible(true);
		}} />
		<Pressable style={styles.under} onPress={(e: NeonEvent): void => { unders += 1; }} />
		<Modal visible={visible()} animationType={fade() ? "fade" : "slide"} onRequestClose={(): void => {
			closes += 1;
			setVisible(false);
		}} onShow={(): void => { shows += 1; }} onDismiss={(): void => { dismissals += 1; }}>
			<Pressable style={styles.sheet} onPress={(e: NeonEvent): void => { setVisible(false); }} />
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
	harnessClick(TITLE, x as int32, y as int32);
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
	harnessExpect("closed: the app shows", 250, 40, 46, 134, 222);
	failures += harnessSample(TITLE);
	click(70.0, 40.0);
});
steps.push((): void => {
	expect("the press opened the Modal", opened === 1 && visible(), `${opened}`);
	expect("onShow fired", shows === 1, `${shows}`);
	harnessExpect("an opaque Modal covers the app", 250, 40, 0, 0, 0);
	harnessExpect("its child draws, faded in", 240, 160, 231, 76, 60);
	failures += harnessSample(TITLE);
	click(250.0, 40.0);
});
steps.push((): void => {
	expect("the Modal takes the click over the app", unders === 0, `${unders}`);
	harnessPostKeys(TITLE, "\u001b");
});
steps.push((): void => {
	expect("Escape asks the app to close", closes === 1 && !visible(), `${closes}`);
	expect("onDismiss fired", dismissals === 1, `${dismissals}`);
	harnessExpect("closed again: the app shows", 250, 40, 46, 134, 222);
	failures += harnessSample(TITLE);
	click(250.0, 40.0);
});
steps.push((): void => {
	expect("the app takes clicks again", unders === 1, `${unders}`);
	setFade(false);
	click(70.0, 40.0);
});
steps.push((): void => {
	harnessExpect("a slid Modal settles in place", 240, 160, 231, 76, 60);
	failures += harnessSample(TITLE);
	click(240.0, 160.0);
});
steps.push((): void => {
	expect("a press inside the Modal closes it", !visible() && closes === 1 && dismissals === 2, `${closes} ${dismissals}`);
	harnessPostKeys(TITLE, "\u001b");
});
steps.push((): void => {
	expect("Escape with no Modal does nothing", closes === 1, `${closes}`);
});

const options = nativeWindowOptions(TITLE, 480, 320);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (): void => {
	setTimeout((): void => { run(0); }, 700);
} : null));
