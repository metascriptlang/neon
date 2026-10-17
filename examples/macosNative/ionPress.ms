// The Pressables of examples/windowsNative/ionPress.ms in a macOS Ion window: hit-testing in child order, transforms,
// and the press, cancel and gesture phases.
//   msc build examples/macosNative/ionPress.ms --output=out/macosIonPress
//   out/macosIonPress            opens the window and logs each press, pressIn and pressOut with its count
//   out/macosIonPress --check    clicks through AppKit mouse events and exits 0 when every step logs what it should

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable } from "../../src/components/primitives";
import { nimStoredAccessibility } from "../../src/platform/macos/handoff.h";
import { harnessIsCheck, harnessPointer } from "./harness.h";
import { exit } from "std/process";

when (macos) {
	@compile("./harness.m");
}

const styles = createStyles({
	base: { width: 400, height: 260, backgroundColor: "#101820" },
	a: { position: "absolute", left: 20, top: 20, width: 140, height: 60, backgroundColor: "#e63a3a", justifyContent: "center", alignItems: "center" },
	b: { position: "absolute", left: 200, top: 20, width: 140, height: 60, backgroundColor: "#1c73d9" },
	cover: { position: "absolute", left: 270, top: 20, width: 70, height: 60, backgroundColor: "#7f8c8d" },
	c: { position: "absolute", left: 20, top: 120, width: 100, height: 100, backgroundColor: "#2ecc71", transform: "scale(0.5)" },
	d: { position: "absolute", left: 200, top: 120, width: 140, height: 60, backgroundColor: "#f1c40f" },
	e: { position: "absolute", left: 130, top: 150, width: 80, height: 20, backgroundColor: "#9b59b6", transform: "rotate(90deg)" },
	label: { color: "#ffffff", fontSize: 20 },
});

const [count, setCount] = createSignal(0);
let presses = 0;
const logged: string[] = [];

function log(line: string): void {
	logged.push(line);
	console.log(line);
}

function pressed(name: string): (e: NeonEvent) => void {
	return (e: NeonEvent): void => {
		presses += 1;
		log(`press ${name} ${presses}`);
		if (name === "A") { setCount(presses); }
	};
}

function note(what: string): (e: NeonEvent) => void {
	return (e: NeonEvent): void => { log(what); };
}

function App(): NeonNode {
	return <View style={styles.base}>
		<Pressable style={styles.a} accessibilityLabel="Press A" onPress={pressed("A")}>
			<Text style={styles.label}>{"A " + count()}</Text>
		</Pressable>
		<Pressable style={styles.b} onPress={pressed("B")} />
		<View style={styles.cover} />
		<Pressable style={styles.c} onPress={pressed("C")} />
		<Pressable style={styles.d} onPress={pressed("D")} onPressIn={note("in D")} onPressOut={note("out D")} />
		<Pressable style={styles.e} onPress={pressed("E")} />
	</View>;
}

const TITLE = "Neon press on Ion";
const DOWN: int32 = 0;
const UP: int32 = 1;
const DRAG: int32 = 2;

interface Step {
	what: string;
	events: int32[];
	expect: string;
}

function click(x: int32, y: int32): int32[] { return [DOWN, x, y, UP, x, y]; }

const steps: Step[] = [
	{ what: "inside A", events: click(50, 50), expect: "press A 1" },
	{ what: "on A's Text, bubbled to A", events: click(90, 50), expect: "press A 2" },
	{ what: "the background", events: click(380, 240), expect: "" },
	{ what: "down in A, up outside", events: [DOWN, 50, 50, UP, 380, 240], expect: "" },
	{ what: "down in A, a move inside, up inside", events: [DOWN, 40, 40, DRAG, 60, 60, UP, 60, 60], expect: "press A 3" },
	{ what: "B's left half", events: click(220, 50), expect: "press B 4" },
	{ what: "B's right half under a later View", events: click(300, 50), expect: "" },
	{ what: "inside scale(0.5) C's visual box", events: click(70, 170), expect: "press C 5" },
	{ what: "C's layout box outside its visual box", events: click(25, 125), expect: "" },
	{ what: "rotate(90deg) E's visual box outside its layout box", events: click(170, 125), expect: "press E 6" },
	{ what: "D where E's unrotated layout box lies", events: click(205, 160), expect: "in D|press D 7|out D" },
	{ what: "D with pressIn and pressOut", events: click(300, 150), expect: "in D|press D 8|out D" },
	{ what: "down in D, up outside", events: [DOWN, 300, 150, UP, 380, 240], expect: "in D|out D" },
];

function runSteps(): void {
	let failures = 0;
	let index = 0;
	const next = (): void => {
		if (index === steps.length) {
			console.log(`${steps.length - failures} of ${steps.length} steps logged what they should`);
			exit(failures);
			return;
		}
		const step = steps[index];
		index += 1;
		logged.splice(0, logged.length);
		for (let i = 0; i + 2 < step.events.length; i += 3) { harnessPointer(TITLE, step.events[i], step.events[i + 1], step.events[i + 2]); }
		setTimeout((): void => {
			const got = logged.join("|");
			const ok = got === step.expect;
			if (!ok) { failures += 1; }
			console.log(`${ok ? "ok  " : "FAIL"} ${step.what}: "${got}"${ok ? "" : `, want "${step.expect}"`}`);
			next();
		}, 300);
	};
	next();
}

const check = harnessIsCheck() !== 0;
const options = nativeWindowOptions(TITLE, 400, 260);
options.topmost = check;
exit(runNativeWindow(options, App, (): void => {
	console.log(`stored label "Press A" on ${nimStoredAccessibility("accessibilityLabel", "Press A")} view, accessible "true" on ${nimStoredAccessibility("accessible", "true")} views`);
	if (check) { setTimeout(runSteps, 500); }
}));
