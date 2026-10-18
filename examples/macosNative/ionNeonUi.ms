// neon-ui's Slider, Picker and DateTimePicker in a macOS Ion window: composed from Views, Text, Pressable and Modal,
// so the bridge has no control of its own for them.
//   msc build examples/macosNative/ionNeonUi.ms --output=out/macosIonNeonUi
//   out/macosIonNeonUi            opens the window and logs each value change
//   out/macosIonNeonUi --check    drags the slider, picks a room and a day through AppKit events, and exits 0 when every
//                                 reported value holds

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { View, Text } from "../../src/components/primitives";
import { Slider } from "../../neon-ui/src/slider";
import { Picker, PickerItem } from "../../neon-ui/src/picker";
import { DateTimePicker } from "../../neon-ui/src/dateTimePicker";
import { harnessIsCheck, harnessClick, harnessPointer, harnessMeasure } from "./harness.h";
import { exit } from "std/process";

when (macos) {
	@compile("./harness.m", "-fobjc-arc");
}

const styles = createStyles({
	base: { width: 480, height: 420, padding: 20, gap: 16, backgroundColor: "#ffffff" },
	slider: { width: 224 },
	label: { color: "#1c1b1f", fontSize: 14 },
});

const ROOMS: PickerItem[] = [{ label: "Standard", value: "std" }, { label: "Deluxe", value: "dlx" }, { label: "Suite", value: "ste" }];
const [guests, setGuests] = createSignal(2.0 as float64);
const [room, setRoom] = createSignal("std");
const [day, setDay] = createSignal("2026-10-07");
let completed: float64 = -1;

function App(): NeonNode {
	return <View style={styles.base}>
		<Slider style={styles.slider} value={guests()} minimumValue={0} maximumValue={8} step={1} accessibilityLabel="Guests"
			onValueChange={(v: float64): void => { console.log(`guests ${v}`); setGuests(v); }}
			onSlidingComplete={(v: float64): void => { completed = v; }} />
		<Picker items={ROOMS} selectedValue={room()} prompt="Room type" accessibilityLabel="Room type"
			onValueChange={(v: string, i: int32): void => { console.log(`room ${v}`); setRoom(v); }} />
		<DateTimePicker value={day()} accessibilityLabel="Check-in" onChange={(v: string): void => { console.log(`day ${v}`); setDay(v); }} />
		<Text style={styles.label}>{`guests ${guests()} · room ${room()} · check-in ${day()}`}</Text>
	</View>;
}

const TITLE = "Neon UI on Ion";
let failures = 0;

function expect(what: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "ok  " : "FAIL"} ${what}: ${detail}`);
	if (!ok) { failures += 1; }
}

// The centre of a labelled view, from its measured bounds "x,y,w,h".
function centre(label: string): int32[] {
	const box: string = harnessMeasure(TITLE, label);
	const parts = box.split(",");
	if (parts.length !== 4) { throw `ionNeonUi: ${label} is not on screen (${box})`; }
	return [(parseFloat(parts[0]) + parseFloat(parts[2]) / 2) as int32, (parseFloat(parts[1]) + parseFloat(parts[3]) / 2) as int32];
}

function click(label: string): void {
	const at = centre(label);
	harnessClick(TITLE, at[0], at[1]);
}

const steps: (() => void)[] = [];

function run(at: number): void {
	if (at >= steps.length) {
		console.log(`failures ${failures}`);
		exit(failures);
		return;
	}
	steps[at]();
	setTimeout((): void => { run(at + 1); }, 500);
}

steps.push((): void => {
	const at = centre("Guests");
	harnessPointer(TITLE, 0, at[0], at[1]);
	harnessPointer(TITLE, 2, at[0] + 40, at[1]);
	harnessPointer(TITLE, 2, at[0] + 75, at[1]);
	harnessPointer(TITLE, 1, at[0] + 75, at[1]);
});
steps.push((): void => {
	expect("a 75 pt drag over a 200 pt track moves 0..8 by 3", guests() === 5, `guests ${guests()}`);
	expect("the release completes the slide", completed === 5, `completed ${completed}`);
	click("Room type");
});
steps.push((): void => { click("Suite"); });
steps.push((): void => {
	expect("the picker reports the chosen room", room() === "ste", `room ${room()}`);
	click("Check-in");
});
steps.push((): void => { click("October 24, 2026"); });
steps.push((): void => { click("OK"); });
steps.push((): void => {
	expect("the date picker reports the chosen day", day() === "2026-10-24", `day ${day()}`);
});

const options = nativeWindowOptions(TITLE, 480, 420);
options.topmost = harnessIsCheck() !== 0;
exit(runNativeWindow(options, App, harnessIsCheck() !== 0 ? (): void => {
	setTimeout((): void => { run(0); }, 700);
} : null));
