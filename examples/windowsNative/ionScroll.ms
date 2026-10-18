// A ScrollView in an Ion window: clip, wheel, onScroll, scrollTo, a press on scrolled content and the scroll bar.
//   msc build examples/windowsNative/ionScroll.ms --output=out/windowsIonScroll.exe
//   out/windowsIonScroll.exe            opens the window and logs each scroll and press
//   out/windowsIonScroll.exe --check    wheels, presses and scrolls by itself, samples its pixels, exits 0 when all match

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/windows/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Pressable, ScrollView, ScrollViewHandle } from "../../src/components/primitives";
import {
	harnessIsCheck, harnessExpect, harnessExpectCount, harnessSample, harnessWheel, harnessClick, harnessHover, harnessDrag,
} from "./harness.h";
import { Window } from "../../../ion/src/index";
import { exit } from "std/process";

when (windows) {
	@compile("./harness.cpp");
	@passL("-ld3d11");
	@passL("-ld2d1");
	@passL("-ldcomp");
	@passL("-ldwmapi");
	@passL("-lgdi32");
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
	barless: { position: "absolute", left: 240, top: 230, width: 140, height: 60, flexGrow: 0 },
	c0: { height: 50, backgroundColor: "#e63a3a" },
	c1: { height: 50, backgroundColor: "#1c73d9" },
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
		<ScrollView style={styles.barless} showsVerticalScrollIndicator={false}>
			<View style={styles.c0} />
			<View style={styles.c1} />
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
	const failures = harnessSample(TITLE) + expectNumber("scrolls from a wheel outside", scrolls, scrollsBeforeOutside) + expectNumber("y unmoved", lastY, 800);
	if (failures !== 0) { exit(failures); }
	(handle as ScrollViewHandle).scrollTo({ y: 0, animated: false });
	setTimeout(barAtRest, 300);
}

// RNW Theme.cpp light colours: the thumb and arrows are black at 0x72, the track white at 0x9E.
const THUMB_ALPHA = 0x72 / 255.0;
const TRACK_ALPHA = 0x9E / 255.0;
const RED: number[] = [230, 58, 58];
const ORANGE: number[] = [230, 126, 34];

function over(top: number, alpha: number, under: number[]): number[] {
	return [
		Math.round(top * alpha + under[0] * (1 - alpha)),
		Math.round(top * alpha + under[1] * (1 - alpha)),
		Math.round(top * alpha + under[2] * (1 - alpha)),
	];
}

function expectColor(name: string, x: number, y: number, c: number[]): void {
	harnessExpect(name, x as int32, y as int32, c[0] as int32, c[1] as int32, c[2] as int32);
}

// The bar's root sits 13 px in from the ScrollView's right edge (window x 207); at rest only a 2 px thumb shows at
// x 214-215, from y 36 for 34 px (168 px of thumb room, 200 of 1000 visible).
function barAtRest(): void {
	expectColor("shy thumb", 214, 52, over(0, THUMB_ALPHA, RED));
	expectColor("shy thumb right column", 215, 52, over(0, THUMB_ALPHA, RED));
	expectColor("track hidden while shy", 209, 52, RED);
	expectColor("no thumb below it", 214, 80, RED);
	expectColor("indicator off: no shy thumb", 375, 250, RED);
	const failures = harnessSample(TITLE);
	if (failures !== 0) { exit(failures); }
	harnessHover(TITLE, 213, 120);
	harnessHover(TITLE, 376, 250);
	setTimeout(barHovered, 300);
}

function barHovered(): void {
	const track = over(255, TRACK_ALPHA, RED);
	expectColor("track under the pointer", 208, 100, track);
	expectColor("full-width thumb", 211, 52, over(0, THUMB_ALPHA, track));
	expectColor("indicator off: nothing on hover", 376, 250, RED);
	const glyph = over(0, THUMB_ALPHA, track);
	harnessExpectCount("first arrow glyph", 207, 24, 12, 12, glyph[0] as int32, glyph[1] as int32, glyph[2] as int32, 40, 8, 100);
	const failures = harnessSample(TITLE);
	if (failures !== 0) { exit(failures); }
	harnessDrag(TITLE, 212, 52, 212, 136, 6);
	setTimeout(afterThumbDrag, 400);
}

// 84 px of thumb travel over 168 px of room is half of the 1000 px range: y 500.
function afterThumbDrag(): void {
	expectColor("band 5 after the drag", 100, 60, ORANGE);
	const failures = harnessSample(TITLE) + expectNumber("y after the thumb drag", lastY, 500);
	if (failures !== 0) { exit(failures); }
	harnessClick(TITLE, 213, 210);
	setTimeout(afterLastArrow, 300);
}

// RNW lineDown is 16 points (c_scrollerLineDelta).
function afterLastArrow(): void {
	const failures = expectNumber("y after the last arrow", lastY, 516);
	if (failures !== 0) { exit(failures); }
	harnessClick(TITLE, 213, 60);
	setTimeout(afterPageUp, 300);
}

// The thumb now starts 87 px down its room, so y 60 is above it: RNW pageUp scrolls by the frame's 200 points.
function afterPageUp(): void {
	exit(expectNumber("y after a press above the thumb", lastY, 316));
}

const options = nativeWindowOptions(TITLE, 400, 300);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (win: Window): void => { setTimeout(atStart, 700); } : null));
