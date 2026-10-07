import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { NeonEvent } from "../../src/render/event";
import { Checkbox } from "../../src/components/checkbox";
import { RadioButton, RadioGroup, RadioOption } from "../../src/components/radio";

function attrOf(n: MockNode, name: string): string {
	for (const a of n.attrs) {
		if (a.name === name) { return a.value ?? ""; }
	}
	return "<none>";
}

function tagged(n: MockNode, tag: string): MockNode[] {
	const out: MockNode[] = [];
	for (const k of n.children) {
		if (k.tag === tag) { out.push(k); }
	}
	return out;
}

function styleOf(n: MockNode): Style {
	return n.style as Style;
}

test "Checkbox is a checkbox whose press reports the toggled value" {
	const [on, setOn] = createSignal(false);
	const root: MockNode = mockNode("root");
	render(element(<Checkbox value={on()} onValueChange={(v: boolean): void => { setOn(v); }} accessibilityLabel="Agree" />), mockHost(), root as unknown as HostNode);
	const box = root.children[0];
	assert mockToString(root) === "<root><pressable accessibilityRole=\"checkbox\" accessibilityLabel=\"Agree\" accessibilityState=\"unchecked\"><view><view><text></text></view></view></pressable></root>", "shape: " + mockToString(root);
	fireEvent(box, "onPress");
	assert on(), "checked after press";
	assert attrOf(box, "accessibilityState") === "checked", "state: " + attrOf(box, "accessibilityState");
	assert mockToString(box).indexOf("✓") > 0, "mark: " + mockToString(box);
	fireEvent(box, "onPress");
	assert !on() && attrOf(box, "accessibilityState") === "unchecked", "unchecked again";
}

test "Checkbox stays put while disabled and reports mixed for indeterminate" {
	const [on, setOn] = createSignal(false);
	const [mixed, setMixed] = createSignal(true);
	const [off, setOff] = createSignal(true);
	let calls = 0;
	const root: MockNode = mockNode("root");
	render(element(<Checkbox value={on()} indeterminate={mixed()} disabled={off()} color="#336699"
		onValueChange={(v: boolean): void => { calls += 1; setOn(v); setMixed(false); }} />), mockHost(), root as unknown as HostNode);
	const box = root.children[0];
	assert attrOf(box, "accessibilityState") === "mixed,disabled", "state: " + attrOf(box, "accessibilityState");
	fireEvent(box, "onPress");
	assert calls === 0, "disabled swallows the press";
	setOff(false);
	assert styleOf(box.children[0]).backgroundColor === "#336699", "tinted when mixed";
	fireEvent(box, "onPress");
	assert calls === 1 && on() && attrOf(box, "accessibilityState") === "checked", "mixed press checks";
}

test "RadioButton shows its status and forwards a press unless disabled" {
	// A literal-union signal is refused (card 2026-10-04-string-literal-union-signal-rejects-its-
	// function-layout): the status is derived from a boolean signal instead.
	const [on, setOn] = createSignal(false);
	const [off, setOff] = createSignal(false);
	let presses = 0;
	const root: MockNode = mockNode("root");
	render(element(<RadioButton value="a" status={on() ? "checked" : "unchecked"} disabled={off()} accessibilityLabel="Apple"
		onPress={(e: NeonEvent): void => { presses += 1; setOn(true); }} />), mockHost(), root as unknown as HostNode);
	const radio = root.children[0];
	assert mockToString(root) === "<root><pressable accessibilityRole=\"radio\" accessibilityLabel=\"Apple\" accessibilityState=\"unchecked\"><view><view><view></view></view></view></pressable></root>", "shape: " + mockToString(root);
	fireEvent(radio, "onPress");
	assert presses === 1 && attrOf(radio, "accessibilityState") === "checked", "checked: " + attrOf(radio, "accessibilityState");
	const dot = radio.children[0].children[0].children[0];
	assert styleOf(dot).backgroundColor === "#2196f3", "dot filled";
	setOff(true);
	fireEvent(radio, "onPress");
	assert presses === 1 && attrOf(radio, "accessibilityState") === "checked,disabled", "disabled: " + attrOf(radio, "accessibilityState");
}

test "RadioGroup renders one radio row per option and selects the pressed one" {
	const [picked, setPicked] = createSignal("b");
	const [opts, setOpts] = createSignal<RadioOption[]>([{ label: "Alpha", value: "a" }, { label: "Beta", value: "b" }]);
	const root: MockNode = mockNode("root");
	render(element(<RadioGroup value={picked()} options={opts()} onValueChange={(v: string): void => { setPicked(v); }} accessibilityLabel="Letter" />), mockHost(), root as unknown as HostNode);
	const group = root.children[0];
	assert group.tag === "view" && attrOf(group, "accessibilityRole") === "radiogroup", "group: " + mockToString(group);
	const rows = tagged(group, "pressable");
	assert rows.length === 2, "rows: " + mockToString(group);
	assert mockToString(rows[0]) === "<pressable accessibilityRole=\"radio\" accessibilityLabel=\"Alpha\" accessibilityState=\"unchecked\"><view><view><view></view></view></view><text>Alpha</text></pressable>", "row: " + mockToString(rows[0]);
	assert attrOf(rows[1], "accessibilityState") === "checked", "initial pick";
	fireEvent(rows[0], "onPress");
	assert picked() === "a", "picked: " + picked();
	assert attrOf(rows[0], "accessibilityState") === "checked" && attrOf(rows[1], "accessibilityState") === "unchecked", "moved";
	setOpts([{ label: "Alpha", value: "a" }, { label: "Beta", value: "b" }, { label: "Gamma", value: "c" }]);
	assert tagged(group, "pressable").length === 3, "options are reactive";
}
