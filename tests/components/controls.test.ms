import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent, fireEventWith } from "../../src/render/host";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { View } from "../../src/components/primitives";
import { Button } from "../../src/components/button";
import { Switch } from "../../src/components/switch";
import { Image } from "../../src/components/image";
import { ActivityIndicator } from "../../src/components/activityIndicator";

function changed(value: string): NeonEvent {
	const e = neonEvent("valuechange");
	e.value = value;
	return e;
}

test "Button is a pressable with the button role whose press stops while disabled" {
	const [disabled, setDisabled] = createSignal(false);
	let presses = 0;
	const root: MockNode = mockNode("root");
	render(element(<Button title="Save" disabled={disabled()} onPress={(e: NeonEvent): void => { presses += 1; }} />), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><pressable accessibilityLabel=\"Save\" accessibilityHint=\"\" accessibilityRole=\"button\"><text>SAVE</text></pressable></root>", "shape: " + mockToString(root);
	const button = root.children[0];
	fireEvent(button, "onPress");
	setDisabled(true);
	fireEvent(button, "onPress");
	assert presses === 1, "presses: " + presses.toString();
	const box = button.style;
	assert box !== null && (box as Style).backgroundColor === "#dfdfdf", "disabled colours";
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
