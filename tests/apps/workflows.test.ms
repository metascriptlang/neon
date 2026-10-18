import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent, fireEventWith } from "../../src/render/host";
import { neonEvent } from "../../src/render/event";
import { SettingsApp } from "../../examples/components/settings";

function byAttr(n: MockNode, name: string, value: string): MockNode | null {
	for (const a of n.attrs) {
		if (a.name === name && a.isDyn && a.dyn() === value) { return n; }
		if (a.name === name && !a.isDyn && a.value === value) { return n; }
	}
	for (const c of n.children) {
		const found = byAttr(c, name, value);
		if (found !== null) { return found; }
	}
	return null;
}

function labelled(root: MockNode, label: string): MockNode {
	const found = byAttr(root, "accessibilityLabel", label);
	if (found === null) { throw "no node labelled " + label + " in " + mockToString(root); }
	return found as MockNode;
}

function type(root: MockNode, label: string, value: string): void {
	const e = neonEvent("changetext");
	e.value = value;
	fireEventWith(labelled(root, label), "onChangeText", e);
	flush();
}

function toggle(root: MockNode, label: string, on: boolean): void {
	const e = neonEvent("valuechange");
	e.value = on ? "true" : "false";
	fireEventWith(labelled(root, label), "onValueChange", e);
	flush();
}

function shows(root: MockNode, text: string): boolean {
	return mockToString(root).indexOf(text) >= 0;
}

// parked: the catalog workflow returns with the product list, see ~/metascript/.inbox/compiler/2026-10-16-function-returning-one-member-is-refused-where-a-function-returning-the-union-is-expected.md

test "settings: return key moves focus, submit saves, toggles switch theme and keep their labels" {
	const root = mockNode("root");
	render(element(<SettingsApp />), mockHost(), root as unknown as HostNode);
	fireEvent(labelled(root, "Name"), "onFocus");
	flush();
	assert shows(root, "Focus: name"), "focus shown";
	type(root, "Name", "Grace Hopper");
	fireEvent(labelled(root, "Name"), "onSubmitEditing");
	flush();
	assert shows(root, "Focus: email"), "return key moved focus to email: " + mockToString(root);
	fireEvent(labelled(root, "Email"), "onSubmitEditing");
	flush();
	assert shows(root, "Saved Grace Hopper &lt;ada@example.com&gt;") || shows(root, "Saved Grace Hopper <ada@example.com>"), "saved: " + mockToString(root);
	assert shows(root, "Focus: none"), "submit blurred the field";
	assert shows(root, "light theme"), "light by default";
	toggle(root, "Use system theme", false);
	toggle(root, "Dark mode", true);
	assert shows(root, "dark theme"), "manual dark theme";
	assert byAttr(root, "accessibilityRole", "header") !== null, "headers carry the header role";
}
