// UI Automation on an Ion window: what Narrator and any UIA client read from the Windows host.
//   msc build examples/windowsNative/ionAutomation.ms --output=out/windowsIonAutomation.exe
//   out/windowsIonAutomation.exe            opens the window with a Pressable, a Switch, a disabled Pressable and a range
//   out/windowsIonAutomation.exe --check    asks the window through the UIA client API and exits 0 when Name, ControlType,
//                                           Invoke, Toggle, Expand, Collapse, SetValue, IsEnabled and RangeValue all answer as the props
//                                           say, and the declared accessibility actions reach onAccessibilityAction
// Ion's window proc does not forward WM_GETOBJECT to Neon yet, so --check routes it with harnessAutomationForward.

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/windows/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal } from "../../src/core/signal";
import { NeonNode, VAttr, VEvent, attr, evt, hostElement } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { View, Text, Pressable } from "../../src/components/primitives";
import { Switch } from "../../src/components/switch";
import {
	harnessIsCheck, harnessAutomationForward, harnessAutomationStart, harnessAutomationDone, harnessAutomationNumber, harnessAutomationText,
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
	base: { width: 400, height: 240, backgroundColor: "#ffffff" },
	press: { position: "absolute", left: 20, top: 20, width: 140, height: 40, backgroundColor: "#1c73d9", justifyContent: "center", alignItems: "center" },
	toggle: { position: "absolute", left: 200, top: 20, width: 40, height: 20 },
	locked: { position: "absolute", left: 20, top: 90, width: 140, height: 40, backgroundColor: "#bdbdbd" },
	range: { position: "absolute", left: 200, top: 90, width: 140, height: 20, backgroundColor: "#2ecc71" },
	menu: { position: "absolute", left: 20, top: 160, width: 140, height: 40, backgroundColor: "#8e44ad" },
	label: { color: "#ffffff", fontSize: 16 },
});

const [on, setOn] = createSignal(false);
let presses = 0;
let flips = 0;
let lastFlip = "";
const acted: string[] = [];

function record(e: NeonEvent): void { acted.push(e.value); }

const rangeStyle: () => Style = (): Style => styles.range;

function rangeBar(): NeonNode {
	const attrs: VAttr[] = [
		attr("accessibilityLabel", "Volume"),
		attr("accessibilityRole", "adjustable"),
		attr("accessibilityValue", "0,100,40,"),
		attr("accessible", "true"),
		attr("accessibilityActions", "setValue"),
	];
	const events: VEvent[] = [evt("onAccessibilityAction", record)];
	return hostElement("view", attrs, events, null, rangeStyle, null);
}

function App(): NeonNode {
	return <View style={styles.base}>
		<Pressable style={styles.press} accessibilityLabel="Press me" accessibilityRole="button" accessibilityHint="Counts a press"
			accessibilityActions={[{ name: "activate" }]} onAccessibilityAction={record}
			onPress={(e: NeonEvent): void => { presses += 1; console.log(`press ${presses}`); }}>
			<Text style={styles.label}>{"Presses " + presses}</Text>
		</Pressable>
		<Switch style={styles.toggle} value={on()} accessibilityLabel="Wi-Fi" onValueChange={(v: boolean): void => {
			flips += 1;
			lastFlip = `${v}`;
			console.log(`flip ${v}`);
			setOn(v);
		}} />
		<Pressable style={styles.locked} accessibilityLabel="Locked" accessibilityRole="button" accessibilityState={{ disabled: true }}
			onPress={(e: NeonEvent): void => { console.log("locked pressed"); }} />
		<Pressable style={styles.menu} accessibilityLabel="Menu" accessibilityRole="button" accessibilityState={{ expanded: false }}
			accessibilityActions={[{ name: "expand" }, { name: "collapse" }]} onAccessibilityAction={record} />
		{rangeBar()}
	</View>;
}

const TITLE = "Neon automation on Ion";
const check = harnessIsCheck() !== 0;
const BUTTON = 50000;
const SLIDER = 50015;
let failures = 0;

function expectNumber(name: string, got: number, want: number): void {
	if (got === want) { return; }
	console.log(`MISMATCH ${name}: got ${got}, want ${want}`);
	failures += 1;
}

function expectText(name: string, got: string, want: string): void {
	if (got === want) { return; }
	console.log(`MISMATCH ${name}: got "${got}", want "${want}"`);
	failures += 1;
}

function poll(waited: number, then: () => void): void {
	if (harnessAutomationDone() !== 0) { then(); return; }
	if (waited > 10000) { console.log("MISMATCH the UIA client did not answer within 10 s"); exit(1); }
	setTimeout((): void => { poll(waited + 50, then); }, 50);
}

function ask(name: string, action: number, then: () => void): void {
	harnessAutomationStart(TITLE, name, action as int32);
	poll(0, (): void => {
		expectNumber(`${name} found`, harnessAutomationNumber("found"), 1);
		then();
	});
}

function number(field: string): number { return harnessAutomationNumber(field); }

function begin(): void {
	harnessAutomationForward(TITLE);
	ask("Press me", 0, pressRead);
}

function pressRead(): void {
	expectText("press name", harnessAutomationText("name"), "Press me");
	expectText("press help", harnessAutomationText("helpText"), "Counts a press");
	expectNumber("press control type", number("controlType"), BUTTON);
	expectNumber("press invoke pattern", number("hasInvoke"), 1);
	expectNumber("press enabled", number("enabled"), 1);
	expectNumber("press control element", number("control"), 1);
	if (number("width") <= 0 || number("height") <= 0) { expectNumber("press bounds", number("width"), 140); }
	ask("Press me", 1, pressInvoked);
}

function pressInvoked(): void {
	expectNumber("invoke result", number("actionResult"), 0);
	setTimeout((): void => {
		expectNumber("presses after Invoke", presses, 1);
		expectText("actions after Invoke", acted.join(","), "activate");
		ask("Wi-Fi", 0, switchRead);
	}, 300);
}

function switchRead(): void {
	expectNumber("switch toggle pattern", number("hasToggle"), 1);
	expectNumber("switch off", number("toggleState"), 0);
	expectNumber("switch control type", number("controlType"), BUTTON);
	expectNumber("switch focusable", number("focusable"), 1);
	ask("Wi-Fi", 2, switchToggled);
}

function switchToggled(): void {
	expectNumber("toggle result", number("actionResult"), 0);
	setTimeout((): void => {
		expectNumber("flip requests", flips, 1);
		expectText("flip asks for", lastFlip, "true");
		ask("Wi-Fi", 0, switchOn);
	}, 300);
}

function switchOn(): void {
	expectNumber("switch on after the flip", number("toggleState"), 1);
	ask("Locked", 0, lockedRead);
}

function lockedRead(): void {
	expectNumber("locked enabled", number("enabled"), 0);
	ask("Volume", 0, rangeRead);
}

function rangeRead(): void {
	expectNumber("range pattern", number("hasRange"), 1);
	expectNumber("range min", number("rangeMin"), 0);
	expectNumber("range max", number("rangeMax"), 100);
	expectNumber("range now", number("rangeNow"), 40);
	expectNumber("range control type", number("controlType"), SLIDER);
	ask("Volume", 5, rangeSet);
}

function rangeSet(): void {
	expectNumber("SetValue result", number("actionResult"), 0);
	setTimeout((): void => {
		expectText("actions after SetValue", acted.join(","), "activate,setValue");
		ask("Menu", 0, menuRead);
	}, 300);
}

function menuRead(): void {
	expectNumber("menu expand pattern", number("hasExpand"), 1);
	expectNumber("menu collapsed", number("expandState"), 0);
	ask("Menu", 3, menuExpanded);
}

function menuExpanded(): void {
	expectNumber("Expand result", number("actionResult"), 0);
	ask("Menu", 4, menuCollapsed);
}

function menuCollapsed(): void {
	expectNumber("Collapse result", number("actionResult"), 0);
	setTimeout((): void => {
		expectText("actions after Expand and Collapse", acted.join(","), "activate,setValue,expand,collapse");
		exit(failures);
	}, 300);
}

const options = nativeWindowOptions(TITLE, 400, 240);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (win: Window): void => { setTimeout(begin, 700); } : null));
