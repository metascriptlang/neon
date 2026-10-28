// The accessibility props of the primitives in a macOS Ion window, read back through NSAccessibility the way VoiceOver
// reads them: role, value, enabled, hidden subtrees, accessibilityPerformPress and custom actions.
//   msc build examples/macosNative/ionAccessibility.ms --output=out/macosIonAccessibility
//   out/macosIonAccessibility            opens the window and logs each press and action
//   out/macosIonAccessibility --check    queries and drives the accessibility tree and exits 0 when every step holds

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable } from "../../src/components/primitives";
import { harnessIsCheck, harnessAccessibility, harnessAccessibilityPress, harnessAccessibilityAction } from "./harness.h";
import { exit } from "std/process";

when (macos) {
	@compile("./harness.m", "-fobjc-arc");
}

const styles = createStyles({
	base: { width: 400, height: 400, backgroundColor: "#101820" },
	row: { height: 28, margin: 4, backgroundColor: "#1c73d9" },
	label: { color: "#ffffff", fontSize: 16 },
});

const logged: string[] = [];

function log(line: string): void {
	logged.push(line);
	console.log(line);
}

function pressed(name: string): (e: NeonEvent) => void {
	return (e: NeonEvent): void => { log(`press ${name}`); };
}

function acted(e: NeonEvent): void { log(`action ${e.value}`); }

function App(): NeonNode {
	return <View style={styles.base}>
		<Pressable style={styles.row} accessible={true} accessibilityLabel="Buy" accessibilityHint="Adds to cart" role="button" onPress={pressed("Buy")} />
		<Pressable style={styles.row} accessible={true} accessibilityLabel="Locked" accessibilityRole="button"
			accessibilityState={{ disabled: true }} onPress={pressed("Locked")} />
		<Pressable style={styles.row} accessible={true} accessibilityLabel="Menu" accessibilityRole="button"
			accessibilityActions={[{ name: "archive", label: "Archive item" }]} onAccessibilityAction={acted} onPress={pressed("Menu")} />
		<Pressable style={styles.row} accessible={true} accessibilityLabel="Open"
			accessibilityActions={[{ name: "activate" }]} onAccessibilityAction={acted} />
		<View style={styles.row} accessible={true} accessibilityLabel="Volume" role="slider"
			accessibilityValue={{ min: 0, max: 10, now: 4, text: "four of ten" }} />
		<View style={styles.row} accessible={true} accessibilityLabel="Mute" role="switch" accessibilityState={{ selected: true }} />
		<View style={styles.row} accessible={true} accessibilityLabel="Both" accessibilityRole="link" role="button" />
		<View style={styles.row} accessible={true} accessibilityLabel="Tree" accessibilityState={{ expanded: true }} />
		<View style={styles.row} accessibilityElementsHidden={true}>
			<View style={styles.row} accessible={true} accessibilityLabel="Secret" />
		</View>
		<View style={styles.row} importantForAccessibility="no-hide-descendants">
			<View style={styles.row} accessible={true} accessibilityLabel="Secret too" />
		</View>
		<View style={styles.row} accessible={true} accessibilityLabel="Skipped" importantForAccessibility="no" />
		<Text style={styles.label}>Hello world</Text>
		<Text style={styles.label} accessibilityLabel="Greeting">Hi</Text>
	</View>;
}

const TITLE = "Neon accessibility on Ion";

interface Step {
	what: string;
	run: () => string;
	expect: string;
	logs?: boolean;
}

function read(label: string): () => string { return (): string => harnessAccessibility(TITLE, label); }

function press(label: string): () => string { return (): string => `${harnessAccessibilityPress(TITLE, label)}`; }

const steps: Step[] = [
	{ what: "role=button with a hint", run: read("Buy"), expect: "AXButton|-|-|-|Adds to cart|1|0|0" },
	{ what: "disabled state", run: read("Locked"), expect: "AXButton|-|-|-|-|0|0|0" },
	{ what: "slider value text over now, with min and max", run: read("Volume"), expect: "AXSlider|four of ten|0|10|-|1|0|0" },
	{ what: "switch role reports selected as its value", run: read("Mute"), expect: "AXCheckBox|1|-|-|-|1|1|0" },
	{ what: "role wins over accessibilityRole", run: read("Both"), expect: "AXButton|-|-|-|-|1|0|0" },
	{ what: "expanded state", run: read("Tree"), expect: "AXUnknown|-|-|-|-|1|0|1" },
	{ what: "accessibilityElementsHidden drops its subtree", run: read("Secret"), expect: "none" },
	{ what: "no-hide-descendants drops its subtree", run: read("Secret too"), expect: "none" },
	{ what: "importantForAccessibility=no is no element", run: read("Skipped"), expect: "none" },
	{ what: "a Text answers its words as its value", run: read("Hello world"), expect: "AXStaticText|Hello world|-|-|-|1|0|0" },
	{ what: "a Text's accessibilityLabel is its value", run: read("Greeting"), expect: "AXStaticText|Greeting|-|-|-|1|0|0" },
	{ what: "accessibilityPerformPress presses a Pressable", run: press("Buy"), expect: "1|press Buy", logs: true },
	{ what: "accessibilityPerformPress is refused when disabled", run: press("Locked"), expect: "0|", logs: true },
	{ what: "accessibilityPerformPress runs the activate action first", run: press("Open"), expect: "1|action activate", logs: true },
	{ what: "a custom action reaches onAccessibilityAction by name", run: (): string => `${harnessAccessibilityAction(TITLE, "Menu", "Archive item")}`, expect: "1|action archive", logs: true },
	{ what: "a view with no press and no activate refuses the press", run: press("Mute"), expect: "0|", logs: true },
];

function runSteps(): void {
	let failures = 0;
	let index = 0;
	const next = (): void => {
		if (index === steps.length) {
			console.log(`${steps.length - failures} of ${steps.length} steps held`);
			exit(failures);
			return;
		}
		const step = steps[index];
		index += 1;
		logged.splice(0, logged.length);
		const got = step.run();
		setTimeout((): void => {
			const result = step.logs === true ? got + "|" + logged.join(",") : got;
			const ok = result === step.expect;
			if (!ok) { failures += 1; }
			console.log(`${ok ? "ok  " : "FAIL"} ${step.what}: "${result}"${ok ? "" : `, want "${step.expect}"`}`);
			next();
		}, 300);
	};
	next();
}

const check = harnessIsCheck() !== 0;
const options = nativeWindowOptions(TITLE, 400, 400);
options.topmost = check;
exit(runNativeWindow(options, App, (): void => {
	if (check) { setTimeout(runSteps, 500); }
}));
