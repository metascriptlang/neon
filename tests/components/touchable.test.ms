// RN's legacy touchables over Pressable. Release waits out Pressable's 130ms
// minimum hold, so each cell awaits past it (see tests/render/press.test.ms).

import { flush } from "../../src/core/runtime";
import { createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { sleepAsync } from "std/core/promise";
import { element } from "../../src/macros/ui/element";
import { NeonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { HostNode, MockNode, mockNode, mockHost, render, fireEvent, fireTouch, mockToString } from "../../src/render/host";
import { Text, View } from "../../src/components/primitives";
import { TouchableOpacity, TouchableHighlight, TouchableWithoutFeedback, TouchableNativeFeedback, NativeFeedback } from "../../src/components/touchable";

let clock = 3000.0;

function touch(node: MockNode, name: string): void {
	clock += 10;
	fireTouch(node, name, 10, 10, clock);
}

function styleOf(n: MockNode): Style {
	return n.style as Style;
}

test "TouchableOpacity fades to activeOpacity while pressed and presses on release" {
	const root = mockNode("root");
	const [log, setLog] = createSignal("");
	createRoot((): void => {
		render(element(<TouchableOpacity style={{ padding: 4 }} onPress={(e: NeonEvent): void => { setLog(log() + "press;"); }}>
			<Text>Tap</Text>
		</TouchableOpacity>), mockHost(), root as unknown as HostNode);
	});
	const box = root.children[0];
	assert mockToString(root) === "<root><pressable accessible=\"true\"><text>Tap</text></pressable></root>", "shape: " + mockToString(root);
	assert styleOf(box).opacity === 1 && styleOf(box).padding === 4, "rest opacity";
	touch(box, "onTouchStart");
	flush();
	assert styleOf(box).opacity === 0.2, "pressed opacity: " + (styleOf(box).opacity ?? -1).toString();
	touch(box, "onTouchEnd");
	flush();
	assert log() === "press;", "press fires on release: " + log();
	await sleepAsync(250);
	assert styleOf(box).opacity === 1, "back to rest after the minimum hold";
}

test "TouchableOpacity honours activeOpacity and the style's own opacity, and does nothing while disabled" {
	const root = mockNode("root");
	const [off, setOff] = createSignal(false);
	const [log, setLog] = createSignal("");
	createRoot((): void => {
		render(element(<TouchableOpacity activeOpacity={0.5} style={{ opacity: 0.9 }} disabled={off()}
			onPress={(e: NeonEvent): void => { setLog(log() + "press;"); }}><Text>Tap</Text></TouchableOpacity>), mockHost(), root as unknown as HostNode);
	});
	const box = root.children[0];
	assert styleOf(box).opacity === 0.9, "rest is the style's opacity";
	touch(box, "onTouchStart");
	flush();
	assert styleOf(box).opacity === 0.5, "activeOpacity";
	touch(box, "onTouchEnd");
	flush();
	await sleepAsync(250);
	setOff(true);
	flush();
	touch(box, "onTouchStart");
	flush();
	assert styleOf(box).opacity === 0.9, "disabled shows no feedback";
	touch(box, "onTouchEnd");
	flush();
	await sleepAsync(250);
	assert log() === "press;", "disabled does not press: " + log();
}

test "TouchableHighlight shows its underlay and dims its child while pressed" {
	const root = mockNode("root");
	createRoot((): void => {
		render(element(<TouchableHighlight underlayColor="#dddddd" style={{ backgroundColor: "#ffffff" }} onPress={(e: NeonEvent): void => {}}>
			<Text>Row</Text>
		</TouchableHighlight>), mockHost(), root as unknown as HostNode);
	});
	const box = root.children[0];
	const child = box.children[0];
	assert mockToString(root) === "<root><pressable accessible=\"true\"><view><text>Row</text></view></pressable></root>", "shape: " + mockToString(root);
	assert styleOf(box).backgroundColor === "#ffffff" && styleOf(child).opacity === 1, "rest";
	touch(box, "onTouchStart");
	flush();
	assert styleOf(box).backgroundColor === "#dddddd" && styleOf(child).opacity === 0.85, "pressed";
	touch(box, "onTouchEnd");
	flush();
	await sleepAsync(250);
	assert styleOf(box).backgroundColor === "#ffffff" && styleOf(child).opacity === 1, "released";
}

test "TouchableHighlight without a background returns to transparent, its underlay defaulting to black" {
	const root = mockNode("root");
	createRoot((): void => {
		render(element(<TouchableHighlight onPress={(e: NeonEvent): void => {}}><Text>Row</Text></TouchableHighlight>), mockHost(), root as unknown as HostNode);
	});
	const box = root.children[0];
	assert styleOf(box).backgroundColor === "transparent", "rest";
	touch(box, "onTouchStart");
	flush();
	assert styleOf(box).backgroundColor === "#000000", "black underlay";
	touch(box, "onTouchEnd");
	flush();
	await sleepAsync(250);
}

test "TouchableWithoutFeedback presses, long-presses and keeps its accessibility props" {
	const root = mockNode("root");
	const [log, setLog] = createSignal("");
	createRoot((): void => {
		render(element(<TouchableWithoutFeedback accessibilityLabel="Card" delayLongPress={100}
			onPress={(e: NeonEvent): void => { setLog(log() + "press;"); }}
			onLongPress={(e: NeonEvent): void => { setLog(log() + "long;"); }}>
			<Text>Card</Text>
		</TouchableWithoutFeedback>), mockHost(), root as unknown as HostNode);
	});
	const box = root.children[0];
	assert mockToString(root) === "<root><pressable accessible=\"true\" accessibilityLabel=\"Card\"><text>Card</text></pressable></root>", "shape: " + mockToString(root);
	touch(box, "onTouchStart");
	flush();
	touch(box, "onTouchEnd");
	flush();
	await sleepAsync(200);
	touch(box, "onTouchStart");
	flush();
	await sleepAsync(200);
	touch(box, "onTouchEnd");
	flush();
	await sleepAsync(200);
	assert log() === "press;long;", "press then long press: " + log();
}

test "Touchable semantic activation respects enabled disabled enabled without feedback" {
	const root = mockNode("root");
	const [off, setOff] = createSignal(false);
	let hits = 0;
	const dispose = createRoot((end: () => void): () => void => {
		render(element(<TouchableOpacity disabled={off()} style={{ opacity: 0.9 }}
			onPress={(): void => { hits += 1; }}><Text>Tap</Text></TouchableOpacity>),
			mockHost(), root as unknown as HostNode);
		return end;
	});
	const button = root.children[0];
	fireEvent(button, "onPress");
	flush();
	assert hits === 1 && styleOf(button).opacity === 0.9, "enabled with no feedback";
	setOff(true);
	flush();
	fireEvent(button, "onPress");
	flush();
	assert hits === 1 && styleOf(button).opacity === 0.9, "disabled stays quiet";
	setOff(false);
	flush();
	fireEvent(button, "onPress");
	flush();
	assert hits === 2 && styleOf(button).opacity === 0.9, "re-enabled with no feedback";
	dispose();
}

function rippleOf(n: MockNode): string {
	for (const a of n.attrs) {
		if (a.name === "androidRipple") { return a.value ?? ""; }
	}
	return "<unset>";
}

test "TouchableNativeFeedback defaults to the selectable background, takes a background and useForeground, and presses" {
	const root = mockNode("root");
	const [foreground, setForeground] = createSignal(false);
	let hits = 0;
	const dispose = createRoot((end: () => void): () => void => {
		render(element(<View>
			<TouchableNativeFeedback onPress={(): void => { hits += 1; }}><Text>a</Text></TouchableNativeFeedback>
			<TouchableNativeFeedback background={NativeFeedback.SelectableBackgroundBorderless(30)} useForeground={foreground()}><Text>b</Text></TouchableNativeFeedback>
			<TouchableNativeFeedback background={NativeFeedback.Ripple("#33ff0000", false)}><Text>c</Text></TouchableNativeFeedback>
		</View>), mockHost(), root as unknown as HostNode);
		return end;
	});
	const kids = root.children[0].children;
	assert rippleOf(kids[0]) === ",false,,false,selectableItemBackground", "default: " + rippleOf(kids[0]);
	assert rippleOf(kids[1]) === ",false,30,false,selectableItemBackgroundBorderless", "borderless: " + rippleOf(kids[1]);
	assert rippleOf(kids[2]) === "#33ff0000,false,,false,", "Ripple: " + rippleOf(kids[2]);
	setForeground(true);
	flush();
	assert rippleOf(kids[1]) === ",false,30,true,selectableItemBackgroundBorderless", "foreground: " + rippleOf(kids[1]);
	fireEvent(kids[0], "onPress");
	flush();
	assert hits === 1, "press fires";
	assert NativeFeedback.canUseNativeForeground() === false, "not Android here";
	dispose();
}
