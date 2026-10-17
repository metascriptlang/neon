// The ScrollView of examples/windowsNative/ionScroll.ms in a macOS Ion window: clip, wheel, onScroll, scrollTo and a press
// on scrolled content.
//   msc build examples/macosNative/ionScroll.ms --output=out/macosIonScroll
//   out/macosIonScroll            opens the window and logs each scroll and press
//   out/macosIonScroll --check    wheels, presses and scrolls by itself, samples its pixels, exits 0 when all match

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Pressable, ScrollView, ScrollViewHandle } from "../../src/components/primitives";
import { harnessIsCheck, harnessExpect, harnessSample, harnessWheel, harnessClick } from "./harness.h";
import { Window } from "../../../ion/src/index";
import { exit } from "std/process";

when (macos) {
	@compile("./harness.m");
}

const styles = createStyles({
	base: { flexGrow: 1, backgroundColor: "#101820" },
	scroll: { position: "absolute", left: 20, top: 20, width: 200, height: 200, flexGrow: 0 },
	b0: { height: 100, backgroundColor: "#e63a3a" },
	b1: { height: 100, backgroundColor: "#1c73d9" },
	b2: { height: 100, backgroundColor: "#2ecc71" },
	b3: { height: 100, backgroundColor: "#f1c40f" },
	b4: { height: 100, backgroundColor: "#9b59b6" },
	b5: { height: 100, backgroundColor: "#e67e22" },
	b6: { height: 100, backgroundColor: "#1abc9c" },
	b7: { height: 100, backgroundColor: "#ecf0f1" },
	b8: { height: 100, backgroundColor: "#34495e" },
	b9: { height: 100, backgroundColor: "#ff00ff" },
});

let lastY = -1.0;
let scrolls = 0;
let pressedBand = "";
let handle: ScrollViewHandle | null = null;
let scrollsBeforeOutside = 0;

function onScroll(e: NeonEvent): void {
	scrolls += 1;
	lastY = e.y;
	console.log(`scroll ${scrolls} y=${e.y}`);
}

function pressed(band: string): (e: NeonEvent) => void {
	return (e: NeonEvent): void => {
		pressedBand = band;
		console.log(`press band ${band}`);
	};
}

function App(): NeonNode {
	return <View style={styles.base}>
		<ScrollView style={styles.scroll} onScroll={onScroll} ref={(h: ScrollViewHandle): void => { handle = h; }}>
			<View style={styles.b0} />
			<View style={styles.b1} />
			<Pressable style={styles.b2} onPress={pressed("2")} />
			<Pressable style={styles.b3} onPress={pressed("3")} />
			<View style={styles.b4} />
			<View style={styles.b5} />
			<View style={styles.b6} />
			<View style={styles.b7} />
			<View style={styles.b8} />
			<View style={styles.b9} />
		</ScrollView>
	</View>;
}

const TITLE = "Neon scroll on Ion";
const check = harnessIsCheck() !== 0;

function expectNumber(name: string, got: number, want: number): int32 {
	if (got === want) { return 0; }
	console.log(`MISMATCH ${name}: got ${got}, want ${want}`);
	return 1;
}

function expectText(name: string, got: string, want: string): int32 {
	if (got === want) { return 0; }
	console.log(`MISMATCH ${name}: got "${got}", want "${want}"`);
	return 1;
}

function atStart(): void {
	harnessExpect("band 0", 100, 60, 230, 58, 58);
	harnessExpect("band 1", 100, 160, 28, 115, 217);
	harnessExpect("clipped below", 100, 250, 16, 24, 32);
	harnessExpect("beside", 300, 100, 16, 24, 32);
	const failures = harnessSample(TITLE) + expectNumber("scrolls before input", scrolls, 0);
	if (failures !== 0) { exit(failures); }
	harnessWheel(TITLE, 100, 100, -240);
	setTimeout(afterWheel, 1300);
}

function afterWheel(): void {
	harnessExpect("band 2 after wheel", 100, 60, 46, 204, 113);
	harnessExpect("band 3 after wheel", 100, 160, 241, 196, 15);
	harnessExpect("still clipped", 100, 250, 16, 24, 32);
	const failures = harnessSample(TITLE) + expectNumber("y after wheel", lastY, 240);
	if (failures !== 0) { exit(failures); }
	harnessClick(TITLE, 100, 160);
	setTimeout(afterClick, 300);
}

function afterClick(): void {
	const failures = expectText("band pressed", pressedBand, "3");
	if (failures !== 0) { exit(failures); }
	(handle as ScrollViewHandle).scrollTo({ y: 900, animated: false });
	setTimeout(afterScrollTo, 300);
}

function afterScrollTo(): void {
	harnessExpect("band 8 at the end", 100, 60, 52, 73, 94);
	harnessExpect("band 9 at the end", 100, 210, 255, 0, 255);
	const failures = harnessSample(TITLE) + expectNumber("y clamped at the end", lastY, 800);
	if (failures !== 0) { exit(failures); }
	scrollsBeforeOutside = scrolls;
	harnessWheel(TITLE, 300, 100, 120);
	setTimeout(afterWheelOutside, 300);
}

function afterWheelOutside(): void {
	harnessExpect("band 8 unmoved", 100, 60, 52, 73, 94);
	exit(harnessSample(TITLE) + expectNumber("scrolls from a wheel outside", scrolls, scrollsBeforeOutside) + expectNumber("y unmoved", lastY, 800));
}

const options = nativeWindowOptions(TITLE, 400, 300);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (win: Window): void => { setTimeout(atStart, 700); } : null));
