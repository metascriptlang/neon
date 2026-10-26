// Switches in an Ion window: a controlled toggle by click and by Space, a switch whose handler refuses the flip, a disabled
// one, and the colour props.
//   msc build examples/windowsNative/ionSwitch.ms --output=out/windowsIonSwitch.exe
//   out/windowsIonSwitch.exe            opens the window and logs each value change
//   out/windowsIonSwitch.exe --check    clicks and presses Space by itself, samples its pixels, exits 0 when all match

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/windows/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { View } from "../../src/components/primitives";
import { Switch } from "../../src/components/switch";
import { harnessIsCheck, harnessExpectCount, harnessSample, harnessClick, harnessHover, harnessPostKeys } from "./harness.h";
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
	base: { flexGrow: 1, backgroundColor: "#ffffff" },
	a: { position: "absolute", left: 20, top: 20, width: 40, height: 20 },
	b: { position: "absolute", left: 100, top: 20, width: 40, height: 20 },
	c: { position: "absolute", left: 180, top: 20, width: 40, height: 20 },
	d: { position: "absolute", left: 260, top: 20, width: 40, height: 20 },
});

const [aOn, setAOn] = createSignal(false);
let aEvents = 0, bEvents = 0, cEvents = 0;
let lastA = "", lastB = "";

function App(): NeonNode {
	return <View style={styles.base}>
		<Switch style={styles.a} value={aOn()} onValueChange={(v: boolean): void => {
			aEvents += 1;
			lastA = `${v}`;
			console.log(`a ${v}`);
			setAOn(v);
		}} />
		<Switch style={styles.b} value={false} onValueChange={(v: boolean): void => {
			bEvents += 1;
			lastB = `${v}`;
			console.log(`b ${v}`);
		}} />
		<Switch style={styles.c} value={false} disabled={true} onValueChange={(v: boolean): void => { cEvents += 1; }} />
		<Switch style={styles.d} value={true} trackColorOn="#e63a3a" thumbColor="#2ecc71" />
	</View>;
}

const TITLE = "Neon switch on Ion";
const check = harnessIsCheck() !== 0;

function expectText(name: string, got: string, want: string): int32 {
	if (got === want) { return 0; }
	console.log(`MISMATCH ${name}: got "${got}", want "${want}"`);
	return 1;
}

function expectNumber(name: string, got: number, want: number): int32 {
	if (got === want) { return 0; }
	console.log(`MISMATCH ${name}: got ${got}, want ${want}`);
	return 1;
}

// RNW Theme.cpp light colours over the white base: black at alpha 6 (off fill), 0x72 (off stroke), 0x9E (off thumb) and
// 0x5C (disabled thumb); the on fill is AccentDark1 and the thumb on it white. Boxes sit inside the track, away from its
// thumb, and count pixels within a few levels of the colour.
const OFF_FILL: number[] = [249, 249, 249];
const OFF_THUMB: number[] = [95, 95, 95];
const OFF_STROKE: number[] = [141, 141, 141];
const DISABLED_THUMB: number[] = [163, 163, 163];
const WHITE: number[] = [255, 255, 255];
const ACCENT: number[] = [0, 95, 184];
const RED: number[] = [230, 58, 58];
const GREEN: number[] = [46, 204, 113];

function box(name: string, x: number, y: number, w: number, h: number, c: number[], tolerance: number): void {
	harnessExpectCount(name, x as int32, y as int32, w as int32, h as int32, c[0] as int32, c[1] as int32, c[2] as int32, tolerance as int32, (w * h) as int32, (w * h) as int32);
}

// A track is 40x20 at its switch's left and top; its thumb is 12x12 at 4 from the left when off and 24 when on.
function off(name: string, left: number, fill: number[], thumb: number[]): void {
	box(`${name} fill`, left + 20, 26, 16, 8, fill, 3);
	box(`${name} thumb`, left + 7, 27, 6, 6, thumb, 4);
}

function on(name: string, left: number, fill: number[], thumb: number[]): void {
	box(`${name} fill`, left + 6, 26, 16, 8, fill, 3);
	box(`${name} thumb`, left + 27, 27, 6, 6, thumb, 4);
}

function atStart(): void {
	off("a rest", 20, OFF_FILL, OFF_THUMB);
	box("a stroke", 30, 20, 20, 1, OFF_STROKE, 6);
	off("b rest", 100, OFF_FILL, OFF_THUMB);
	off("c disabled", 180, WHITE, DISABLED_THUMB);
	on("d colours", 260, RED, GREEN);
	const failures = harnessSample(TITLE) + expectNumber("events before input", aEvents + bEvents + cEvents, 0);
	if (failures !== 0) { exit(failures); }
	harnessClick(TITLE, 120, 30);
	harnessClick(TITLE, 200, 30);
	harnessHover(TITLE, 200, 150);
	setTimeout(afterBAndC, 300);
}

function afterBAndC(): void {
	off("b follows value", 100, OFF_FILL, OFF_THUMB);
	off("c ignores the click", 180, WHITE, DISABLED_THUMB);
	const failures = harnessSample(TITLE) + expectNumber("b events", bEvents, 1) + expectText("b value asked", lastB, "true") + expectNumber("c events", cEvents, 0);
	if (failures !== 0) { exit(failures); }
	harnessClick(TITLE, 40, 30);
	harnessHover(TITLE, 200, 150);
	setTimeout(afterAClick, 300);
}

function afterAClick(): void {
	on("a on", 20, ACCENT, WHITE);
	const failures = harnessSample(TITLE) + expectNumber("a events", aEvents, 1) + expectText("a value asked", lastA, "true");
	if (failures !== 0) { exit(failures); }
	harnessPostKeys(TITLE, " ");
	setTimeout(afterSpace, 300);
}

function afterSpace(): void {
	off("a off by Space", 20, OFF_FILL, OFF_THUMB);
	const failures = harnessSample(TITLE) + expectNumber("a events", aEvents, 2) + expectText("a value asked", lastA, "false");
	if (failures !== 0) { exit(failures); }
	harnessHover(TITLE, 120, 30);
	setTimeout(afterHover, 300);
}

// Hovering widens the thumb from 12 to 14 points: column 117 of b's track is thumb only then, at the rows the round end still covers.
function afterHover(): void {
	box("b hover thumb", 117, 29, 1, 2, [91, 91, 91], 6);
	exit(harnessSample(TITLE));
}

const options = nativeWindowOptions(TITLE, 400, 200);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (win: Window): void => { setTimeout(atStart, 700); } : null));
