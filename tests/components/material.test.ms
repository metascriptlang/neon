import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { NeonEvent } from "../../src/render/event";
import { Checkbox } from "../../src/components/checkbox";
import { RadioButton, RadioGroup, RadioOption } from "../../src/components/radio";
import { SegmentedControl } from "../../src/components/segmentedControl";
import { Chip } from "../../src/components/chip";
import { Card, CardActions, CardContent, CardTitle } from "../../src/components/card";
import { Avatar } from "../../src/components/avatar";
import { Badge } from "../../src/components/badge";
import { Divider } from "../../src/components/divider";
import { Text, View } from "../../src/components/primitives";

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

test "SegmentedControl is a tablist of tabs that reports index and value" {
	const [index, setIndex] = createSignal(0);
	const [on, setOn] = createSignal(true);
	let log = "";
	const root: MockNode = mockNode("root");
	render(element(<SegmentedControl values={["Day", "Week"]} selectedIndex={index()} enabled={on()}
		onChange={(i: int32): void => { log += "i" + i.toString() + ";"; setIndex(i); }}
		onValueChange={(v: string): void => { log += v + ";"; }} />), mockHost(), root as unknown as HostNode);
	const bar = root.children[0];
	assert attrOf(bar, "accessibilityRole") === "tablist", "bar: " + mockToString(bar);
	const tabs = tagged(bar, "pressable");
	assert tabs.length === 2, "tabs: " + mockToString(bar);
	assert mockToString(tabs[0]) === "<pressable accessibilityRole=\"tab\" accessibilityLabel=\"Day\" accessibilityState=\"selected\"><text>Day</text></pressable>", "tab: " + mockToString(tabs[0]);
	assert attrOf(tabs[1], "accessibilityState") === "", "unselected: " + attrOf(tabs[1], "accessibilityState");
	fireEvent(tabs[0], "onPress");
	fireEvent(tabs[1], "onPress");
	assert log === "i1;Week;", "log: " + log;
	assert attrOf(tabs[1], "accessibilityState") === "selected" && attrOf(tabs[0], "accessibilityState") === "", "moved";
	assert styleOf(tabs[1]).backgroundColor === "#2196f3", "selected tint";
	setOn(false);
	fireEvent(tabs[0], "onPress");
	assert log === "i1;Week;" && attrOf(tabs[0], "accessibilityState") === "disabled", "disabled: " + attrOf(tabs[0], "accessibilityState");
}

test "Chip is a toggle button once selectable and closes through its own button" {
	const [chosen, setChosen] = createSignal(false);
	let closed = 0;
	const root: MockNode = mockNode("root");
	render(element(<Chip label="Pizza" selected={chosen()} mode="outlined" onPress={(e: NeonEvent): void => { setChosen(!chosen()); }}
		onClose={(): void => { closed += 1; }} />), mockHost(), root as unknown as HostNode);
	const shell = root.children[0];
	const body = shell.children[0].children[0];
	const closer = shell.children[0].children[1];
	assert mockToString(body) === "<pressable accessibilityRole=\"togglebutton\" accessibilityLabel=\"Pizza\" accessibilityState=\"\"><text></text><text>Pizza</text></pressable>", "body: " + mockToString(body);
	assert mockToString(closer) === "<pressable accessibilityRole=\"button\" accessibilityLabel=\"Close\"><text>×</text></pressable>", "close: " + mockToString(closer);
	assert styleOf(shell).padding === 1, "outlined shell";
	fireEvent(body, "onPress");
	assert chosen() && attrOf(body, "accessibilityState") === "selected", "selected: " + attrOf(body, "accessibilityState");
	assert mockToString(body).indexOf("✓") > 0, "check shown: " + mockToString(body);
	fireEvent(closer, "onPress");
	assert closed === 1, "closed";
}

test "Chip without selection is a plain button and ignores presses while disabled" {
	const [off, setOff] = createSignal(true);
	let presses = 0;
	const root: MockNode = mockNode("root");
	render(element(<Chip icon="★" disabled={off()} onPress={(e: NeonEvent): void => { presses += 1; }}>Starred</Chip>), mockHost(), root as unknown as HostNode);
	const body = root.children[0].children[0].children[0];
	assert mockToString(body) === "<pressable accessibilityRole=\"button\" accessibilityState=\"disabled\"><text>★</text><text>Starred</text></pressable>", "body: " + mockToString(body);
	fireEvent(body, "onPress");
	setOff(false);
	fireEvent(body, "onPress");
	assert presses === 1, "presses: " + presses.toString();
}

test "Card is a surface over a darker elevation edge and a button once pressable" {
	const [level, setLevel] = createSignal(2);
	let presses = 0;
	const root: MockNode = mockNode("root");
	render(element(<View>
		<Card elevation={level()} style={{ margin: 8, backgroundColor: "#fafafa" }} onPress={(e: NeonEvent): void => { presses += 1; }} accessibilityLabel="Order">
			<CardTitle title="Order" subtitle="Two items" />
			<CardContent><Text>Body</Text></CardContent>
			<CardActions><Text>OK</Text></CardActions>
		</Card>
		<Card><Text>Plain</Text></Card>
	</View>), mockHost(), root as unknown as HostNode);
	const card = root.children[0].children[0];
	assert mockToString(card) === "<pressable accessibilityRole=\"button\" accessibilityLabel=\"Order\"><view><view><text accessibilityRole=\"header\">Order</text><text>Two items</text></view><view><text>Body</text></view><view><text>OK</text></view></view></pressable>", "card: " + mockToString(card);
	assert styleOf(card).paddingBottom === 2 && styleOf(card).margin === 8 && styleOf(card).backgroundColor === "#d0d0d0", "edge";
	assert styleOf(card.children[0]).backgroundColor === "#fafafa", "surface takes the caller's background";
	fireEvent(card, "onPress");
	assert presses === 1, "pressed";
	setLevel(9);
	assert styleOf(card).paddingBottom === 5, "elevation clamps at 5";
	const plain = root.children[0].children[1];
	assert mockToString(plain) === "<view><view><text>Plain</text></view></view>", "plain: " + mockToString(plain);
	assert styleOf(plain).paddingBottom === 1 && styleOf(plain.children[0]).backgroundColor === "#ffffff", "default surface";
}

test "Avatar shows initials or an image as one labelled round image" {
	const [size, setSize] = createSignal(40);
	const root: MockNode = mockNode("root");
	render(element(<View>
		<Avatar label="JD" size={size()} backgroundColor="#336699" />
		<Avatar source={{ uri: "https://example.com/me.png" }} accessibilityLabel="Me" />
	</View>), mockHost(), root as unknown as HostNode);
	const initials = root.children[0].children[0];
	const picture = root.children[0].children[1];
	assert mockToString(initials) === "<view accessibilityRole=\"image\" accessibilityLabel=\"JD\"><text>JD</text></view>", "initials: " + mockToString(initials);
	assert styleOf(initials).borderRadius === 20 && styleOf(initials).backgroundColor === "#336699", "round";
	setSize(64);
	assert styleOf(initials).width === 64 && styleOf(initials).borderRadius === 32, "size is reactive";
	assert mockToString(picture) === "<view accessibilityRole=\"image\" accessibilityLabel=\"Me\"><image source=\"https://example.com/me.png\" resizeMode=\"cover\" accessibilityRole=\"image\" accessible=\"false\"></image></view>", "picture: " + mockToString(picture);
}

test "Badge holds a value or shrinks to a dot, and hides when not visible" {
	const [count, setCount] = createSignal(3);
	const [shown, setShown] = createSignal(true);
	const root: MockNode = mockNode("root");
	render(element(<View>
		<Badge value={count().toString()} visible={shown()} />
		<Badge />
	</View>), mockHost(), root as unknown as HostNode);
	const badge = root.children[0].children[0];
	const dot = root.children[0].children[1];
	assert mockToString(badge) === "<view accessibilityRole=\"text\" accessibilityLabel=\"3\"><text>3</text></view>", "badge: " + mockToString(badge);
	setCount(12);
	assert mockToString(badge).indexOf("<text>12</text>") > 0, "value follows: " + mockToString(badge);
	assert styleOf(badge).height === 20 && styleOf(dot).height === 6, "sizes";
	assert mockToString(dot) === "<view></view>", "dot: " + mockToString(dot);
	setShown(false);
	assert styleOf(badge).display === "none", "hidden";
}

test "Divider is a filled line, horizontal or vertical, with insets" {
	const root: MockNode = mockNode("root");
	render(element(<View>
		<Divider inset={true} thickness={2.0} color="#ff0000" />
		<Divider vertical={true} indent={4.0} />
	</View>), mockHost(), root as unknown as HostNode);
	const line = styleOf(root.children[0].children[0]);
	const column = styleOf(root.children[0].children[1]);
	assert line.height === 2 && line.marginLeft === 16 && line.backgroundColor === "#ff0000", "horizontal";
	assert column.width === 1 && column.marginTop === 4 && column.backgroundColor === "#e0e0e0", "vertical";
}
