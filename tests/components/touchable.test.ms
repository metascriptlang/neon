// RN's legacy touchables over Pressable. Release waits out Pressable's 130ms
// minimum hold, so each cell awaits past it (see tests/render/press.test.ms).

import { createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { sleepAsync } from "std/core/promise";
import { element } from "../../src/macros/ui/element";
import { NeonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { HostNode, MockNode, mockNode, mockHost, render, fireEvent, mockToString } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import { TouchableOpacity, TouchableHighlight, TouchableWithoutFeedback } from "../../src/components/touchable";

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
	fireEvent(box, "onPointerDown");
	assert styleOf(box).opacity === 0.2, "pressed opacity: " + (styleOf(box).opacity ?? -1).toString();
	fireEvent(box, "onPointerUp");
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
	fireEvent(box, "onPointerDown");
	assert styleOf(box).opacity === 0.5, "activeOpacity";
	fireEvent(box, "onPointerUp");
	await sleepAsync(250);
	setOff(true);
	fireEvent(box, "onPointerDown");
	assert styleOf(box).opacity === 0.9, "disabled shows no feedback";
	fireEvent(box, "onPointerUp");
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
	fireEvent(box, "onPointerDown");
	assert styleOf(box).backgroundColor === "#dddddd" && styleOf(child).opacity === 0.85, "pressed";
	fireEvent(box, "onPointerUp");
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
	fireEvent(box, "onPointerDown");
	assert styleOf(box).backgroundColor === "#000000", "black underlay";
	fireEvent(box, "onPointerUp");
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
	fireEvent(box, "onPointerDown");
	fireEvent(box, "onPointerUp");
	await sleepAsync(200);
	fireEvent(box, "onPointerDown");
	await sleepAsync(200);
	fireEvent(box, "onPointerUp");
	await sleepAsync(200);
	assert log() === "press;long;", "press then long press: " + log();
}
