// The Neon-drawn overlay and flow controls. Timers are the std timer on every lane, so a
// timed cell awaits past its deadline with wide margins and records into a signal: no
// mutable local is read after an await (tests/render/press.test.ms).

import { createSignal } from "../../src/core/signal";
import { sleepAsync } from "std/core/promise";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { Text } from "../../src/components/primitives";
import { Snackbar } from "../../src/components/snackbar";
import { Toast, ToastHost, currentToast } from "../../src/components/toast";
import { Tooltip } from "../../src/components/tooltip";

function firstTag(parent: MockNode, tag: string): MockNode {
	for (const c of parent.children) {
		if (c.tag === tag) { return c; }
	}
	throw "no <" + tag + "> under <" + parent.tag + ">";
}

test "Snackbar shows a bottom alert with its action, and the action dismisses it" {
	const [open, setOpen] = createSignal(false);
	const [log, setLog] = createSignal("");
	const root: MockNode = mockNode("root");
	render(element(<Snackbar visible={open()} message="Saved" actionLabel="Undo"
		onActionPress={(): void => { setLog(log() + "undo;"); }}
		onDismiss={(): void => { setLog(log() + "dismiss;"); setOpen(false); }} />), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root></root>", "hidden: " + mockToString(root);
	setOpen(true);
	assert mockToString(root) === "<root><view accessibilityLabel=\"Saved\" accessibilityRole=\"alert\"><view><text>Saved</text></view><pressable accessibilityLabel=\"Undo\" accessibilityRole=\"button\"><text>UNDO</text></pressable></view></root>", "shown: " + mockToString(root);
	const bar = root.children[0];
	const layer = bar.style as Style;
	assert layer.position === "absolute" && layer.bottom === 8 && layer.backgroundColor === "#323232", "pinned to the bottom";
	fireEvent(bar.children[1], "onPress");
	assert log() === "undo;dismiss;", "action: " + log();
	assert mockToString(root) === "<root></root>", "dismissed: " + mockToString(root);
}

test "Snackbar dismisses itself after its duration and not while hidden" {
	const [open, setOpen] = createSignal(false);
	const [dismissed, setDismissed] = createSignal(0);
	const root: MockNode = mockNode("root");
	render(element(<Snackbar visible={open()} duration={120}
		onDismiss={(): void => { setDismissed(dismissed() + 1); setOpen(false); }}><Text>Archived</Text></Snackbar>), mockHost(), root as unknown as HostNode);
	await sleepAsync(200);
	assert dismissed() === 0, "no timer while hidden";
	setOpen(true);
	assert mockToString(root) === "<root><view accessibilityLabel=\"\" accessibilityRole=\"alert\"><view><text>Archived</text></view></view></root>", "children: " + mockToString(root);
	await sleepAsync(40);
	assert dismissed() === 0, "too early";
	await sleepAsync(160);
	assert dismissed() === 1 && mockToString(root) === "<root></root>", "auto-dismissed: " + dismissed().toString();
	setOpen(true);
	setOpen(false);
	await sleepAsync(200);
	assert dismissed() === 1, "hiding clears the timer: " + dismissed().toString();
}

test "Snackbar takes paper's action object and an accent colour" {
	const [log, setLog] = createSignal("");
	const root: MockNode = mockNode("root");
	render(element(<Snackbar visible={true} message="Deleted" actionColor="#ffcc80"
		action={{ label: "Retry", onPress: (): void => { setLog(log() + "retry;"); } }}
		onDismiss={(): void => { setLog(log() + "dismiss;"); }} />), mockHost(), root as unknown as HostNode);
	const button = root.children[0].children[1];
	assert mockToString(button) === "<pressable accessibilityLabel=\"Retry\" accessibilityRole=\"button\"><text>RETRY</text></pressable>", "action: " + mockToString(button);
	assert (button.children[0].style as Style).color === "#ffcc80", "accent";
	fireEvent(button, "onPress");
	assert log() === "retry;dismiss;", "presses: " + log();
}

test "Toast.show reaches the ToastHost, Toast.hide and the timer take it away" {
	const root: MockNode = mockNode("root");
	render(element(<ToastHost />), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root></root>", "idle: " + mockToString(root);
	Toast.show({ text1: "Saved", text2: "Draft stored", type: "success" });
	assert mockToString(root) === "<root><view><view accessibilityLabel=\"Saved, Draft stored\" accessibilityRole=\"alert\"><view></view><view><text>Saved</text><text>Draft stored</text></view></view></view></root>", "shown: " + mockToString(root);
	const layer = root.children[0];
	assert (layer.style as Style).bottom === 40 && (layer.style as Style).position === "absolute", "near the bottom";
	assert (layer.children[0].children[0].style as Style).backgroundColor === "#4caf50", "success dot";
	Toast.hide();
	assert mockToString(root) === "<root></root>", "hidden: " + mockToString(root);
	Toast.show({ text1: "Offline", type: "error", position: "top", visibilityTime: 120 });
	assert mockToString(root) === "<root><view><view accessibilityLabel=\"Offline\" accessibilityRole=\"alert\"><view></view><view><text>Offline</text></view></view></view></root>", "one line: " + mockToString(root);
	assert (root.children[0].style as Style).top === 40, "top position";
	await sleepAsync(40);
	assert currentToast() !== null, "still up";
	await sleepAsync(160);
	assert currentToast() === null && mockToString(root) === "<root></root>", "timed out: " + mockToString(root);
}

test "a second Toast.show replaces the first and restarts the timer" {
	const root: MockNode = mockNode("root");
	render(element(<ToastHost />), mockHost(), root as unknown as HostNode);
	Toast.show({ text1: "One", visibilityTime: 150 });
	await sleepAsync(100);
	Toast.show({ text1: "Two", visibilityTime: 150 });
	await sleepAsync(100);
	assert mockToString(root).indexOf("<text>Two</text>") > 0, "replaced and still up: " + mockToString(root);
	Toast.show({ text1: "Sticky", autoHide: false, visibilityTime: 50 });
	await sleepAsync(120);
	assert mockToString(root).indexOf("<text>Sticky</text>") > 0, "autoHide false stays";
	Toast.hide();
	assert currentToast() === null, "hidden";
}

test "Tooltip shows its title above the child on a long press and leaves after the release" {
	const root: MockNode = mockNode("root");
	render(element(<Tooltip title="Delete" enterTouchDelay={60} leaveTouchDelay={120}>
		<Text>trash</Text>
	</Tooltip>), mockHost(), root as unknown as HostNode);
	const wrapper = root.children[0];
	assert mockToString(root) === "<root><pressable accessibilityHint=\"Delete\"><text>trash</text></pressable></root>", "idle: " + mockToString(root);
	fireEvent(wrapper, "onPointerDown");
	await sleepAsync(20);
	assert mockToString(wrapper).indexOf("<view>") < 0, "not before the enter delay";
	await sleepAsync(150);
	assert mockToString(wrapper) === "<pressable accessibilityHint=\"Delete\"><text>trash</text><view><text>Delete</text></view></pressable>", "bubble: " + mockToString(wrapper);
	const bubble = firstTag(wrapper, "view").style as Style;
	assert bubble.position === "absolute" && bubble.top === -40 && bubble.backgroundColor === "#616161", "above the child";
	fireEvent(wrapper, "onPointerUp");
	await sleepAsync(40);
	assert mockToString(wrapper).indexOf("<view>") > 0, "stays for the leave delay";
	await sleepAsync(160);
	assert mockToString(wrapper) === "<pressable accessibilityHint=\"Delete\"><text>trash</text></pressable>", "left: " + mockToString(wrapper);
}
