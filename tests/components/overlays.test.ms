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
