import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent, fireEventWith } from "../../src/render/host";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { View, Text } from "../../src/components/primitives";
import { ImageBackground } from "../../src/components/imageBackground";
import { Button } from "../../src/components/button";
import { Switch } from "../../src/components/switch";
import { Image } from "../../src/components/image";
import { ActivityIndicator } from "../../src/components/activityIndicator";

function changed(value: string): NeonEvent {
	const e = neonEvent("valuechange");
	e.value = value;
	return e;
}

when (ios) {
	const SAVE_TITLE = "Save";
} else {
	const SAVE_TITLE = "SAVE";
}

test "Button is a pressable with the button role whose press stops while disabled" {
	const [disabled, setDisabled] = createSignal(false);
	let presses = 0;
	const root: MockNode = mockNode("root");
	render(element(<Button title="Save" disabled={disabled()} onPress={(e: NeonEvent): void => { presses += 1; }} />), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><pressable accessible=\"true\" accessibilityLabel=\"Save\" accessibilityHint=\"\" accessibilityRole=\"button\"><text>" + SAVE_TITLE + "</text></pressable></root>", "shape: " + mockToString(root);
	const button = root.children[0];
	fireEvent(button, "onPress");
	setDisabled(true);
	fireEvent(button, "onPress");
	assert presses === 1, "presses: " + presses.toString();
}

when (ios) {
	test "Button on iOS is RN's text-only button: tinted 18pt label, #cdcdcd when disabled, no box" {
		const [disabled, setDisabled] = createSignal(false);
		const root: MockNode = mockNode("root");
		render(element(<Button title="Go" disabled={disabled()} />), mockHost(), root as unknown as HostNode);
		const button = root.children[0];
		assert (button.style as Style).backgroundColor === null, "no box colour";
		const label = (): Style => button.children[0].style as Style;
		assert label().color === "#007AFF" && label().fontSize === 18 && label().margin === 8, "label";
		setDisabled(true);
		assert label().color === "#cdcdcd", "disabled label: " + (label().color ?? "none");
	}
} else {
	test "Button off iOS is RN's Material button: tinted box, radius 2, white uppercase label, grey when disabled" {
		const [disabled, setDisabled] = createSignal(false);
		const root: MockNode = mockNode("root");
		render(element(<Button title="Go" color="#ff0000" disabled={disabled()} />), mockHost(), root as unknown as HostNode);
		const box = (): Style => root.children[0].style as Style;
		const label = (): Style => root.children[0].children[0].style as Style;
		assert box().backgroundColor === "#ff0000" && box().borderRadius === 2, "box: " + (box().backgroundColor ?? "none");
		assert label().color === "#ffffff" && label().margin === 8 && label().fontWeight === "bold", "label";
		setDisabled(true);
		assert box().backgroundColor === "#dfdfdf" && label().color === "#a1a1a1", "disabled colours";
	}
}

test "Switch reports a boolean and follows its controlled value" {
	const [on, setOn] = createSignal(false);
	const root: MockNode = mockNode("root");
	render(element(<Switch value={on()} onValueChange={(v: boolean): void => { setOn(v); }} accessibilityLabel="Wi-Fi" />), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><switch value=\"false\" accessibilityLabel=\"Wi-Fi\"></switch></root>", "shape: " + mockToString(root);
	fireEventWith(root.children[0], "onValueChange", changed("true"));
	assert on() && mockToString(root).indexOf("value=\"true\"") > 0, "toggled: " + mockToString(root);
}

test "Image sends its source and resize mode, and onLoadEnd follows both load and error" {
	const [uri, setUri] = createSignal("https://example.com/a.png");
	let log = "";
	const root: MockNode = mockNode("root");
	render(element(<Image source={{ uri: uri() }} resizeMode="contain" style={{ width: 40, height: 40 }} accessibilityLabel="Avatar"
		onLoadStart={(): void => { log += "start;"; }}
		onLoad={(e: NeonEvent): void => { log += "load;"; }}
		onError={(e: NeonEvent): void => { log += "error;"; }}
		onLoadEnd={(): void => { log += "end;"; }} />), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><image source=\"https://example.com/a.png\" resizeMode=\"contain\" accessibilityRole=\"image\" accessibilityLabel=\"Avatar\"></image></root>", "shape: " + mockToString(root);
	fireEvent(root.children[0], "onLoad");
	setUri("https://example.com/b.png");
	fireEvent(root.children[0], "onError");
	assert log === "start;load;end;start;error;end;", "events: " + log;
}

test "ActivityIndicator sizes small and large like RN and keeps animating reactive" {
	const [busy, setBusy] = createSignal(true);
	const root: MockNode = mockNode("root");
	render(element(<View><ActivityIndicator animating={busy()} size="large" color="#336699" /><ActivityIndicator /></View>), mockHost(), root as unknown as HostNode);
	const large = root.children[0].children[0];
	const small = root.children[0].children[1];
	assert mockToString(large) === "<activityindicator animating=\"true\" color=\"#336699\" accessibilityRole=\"progressbar\"></activityindicator>", "shape: " + mockToString(large);
	assert (large.style as Style).width === 36 && (small.style as Style).width === 20, "sizes";
	setBusy(false);
	assert mockToString(large).indexOf("animating=\"false\"") > 0, "animating follows the signal";
}

test "ImageBackground stretches its image under the children and keeps the box style on the View" {
	const root: MockNode = mockNode("root");
	let loads = 0;
	render(element(<ImageBackground source={{ uri: "https://example.com/bg.png" }} resizeMode="cover" style={{ height: 120, padding: 8 }}
		imageStyle={{ borderRadius: 6 }} onLoad={(e: NeonEvent): void => { loads += 1; }}>
		<Text>Over</Text>
	</ImageBackground>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><view><image source=\"https://example.com/bg.png\" resizeMode=\"cover\" accessibilityRole=\"image\"></image><text>Over</text></view></root>", "shape: " + mockToString(root);
	const box = root.children[0].style as Style;
	const fill = root.children[0].children[0].style as Style;
	assert box.height === 120 && box.padding === 8, "box style";
	assert fill.position === "absolute" && fill.top === 0 && fill.bottom === 0 && fill.left === 0 && fill.right === 0 && fill.borderRadius === 6, "image fills the box";
	fireEvent(root.children[0].children[0], "onLoad");
	assert loads === 1, "onLoad reaches the author";
}

test "Text forwards numberOfLines, ellipsizeMode and selectable, and stays a plain text without them" {
	const [lines, setLines] = createSignal(2);
	const root: MockNode = mockNode("root");
	render(element(<View><Text numberOfLines={lines()} ellipsizeMode="middle" selectable={true}>long</Text><Text>plain</Text></View>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><view><text numberOfLines=\"2\" ellipsizeMode=\"middle\" selectable=\"true\">long</text><text>plain</text></view></root>", "shape: " + mockToString(root);
	setLines(0);
	assert mockToString(root).indexOf("numberOfLines=\"0\"") > 0, "reactive";
}
