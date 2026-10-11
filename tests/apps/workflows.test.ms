import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent, fireEventWith } from "../../src/render/host";
import { neonEvent } from "../../src/render/event";
import { sleepAsync } from "std/core/promise";
import { CatalogApp } from "../../examples/components/catalog";
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
}

function toggle(root: MockNode, label: string, on: boolean): void {
	const e = neonEvent("valuechange");
	e.value = on ? "true" : "false";
	fireEventWith(labelled(root, label), "onValueChange", e);
}

function shows(root: MockNode, text: string): boolean {
	return mockToString(root).indexOf(text) >= 0;
}

test "catalog: list, search, empty, offline error and retry, detail, invalid edit and save" {
	const root = mockNode("root");
	render(element(<CatalogApp />), mockHost(), root as unknown as HostNode);
	assert shows(root, "Loading products"), "loading state first";
	await sleepAsync(700);
	assert shows(root, "12 products") && shows(root, "Walnut desk tray"), "the list loaded";
	type(root, "Search products", "mug");
	await sleepAsync(700);
	assert shows(root, "1 product<") && shows(root, "Ceramic mug") && !shows(root, "Brass pen"), "search filters";
	type(root, "Search products", "zzz");
	await sleepAsync(700);
	assert shows(root, "No products match &quot;zzz&quot;") || shows(root, "No products match \"zzz\""), "empty state: " + mockToString(root);
	type(root, "Search products", "");
	toggle(root, "Simulate offline", true);
	await sleepAsync(700);
	assert shows(root, "Could not reach the catalog"), "error state";
	toggle(root, "Simulate offline", false);
	await sleepAsync(700);
	assert shows(root, "12 products"), "retry after reconnecting";
	fireEvent(labelled(root, "Ceramic mug, $18"), "onPress");
	assert shows(root, "Edit") && shows(root, "Stoneware"), "detail screen";
	fireEvent(labelled(root, "Edit"), "onPress");
	type(root, "Title", " ");
	fireEvent(labelled(root, "Save"), "onPress");
	await sleepAsync(700);
	assert shows(root, "Title is required."), "validation error";
	type(root, "Title", "Ceramic cup");
	type(root, "Price", "21");
	fireEvent(labelled(root, "Save"), "onPress");
	assert shows(root, "SAVING"), "saving state";
	await sleepAsync(1200);
	assert shows(root, "Ceramic cup") && shows(root, "$21") && shows(root, "EDIT"), "saved detail";
	fireEvent(labelled(root, "Back to catalog"), "onPress");
	await sleepAsync(700);
	assert byAttr(root, "accessibilityLabel", "Ceramic cup, $21") !== null, "the list shows the saved row";
}

test "settings: return key moves focus, submit saves, toggles switch theme and keep their labels" {
	const root = mockNode("root");
	render(element(<SettingsApp />), mockHost(), root as unknown as HostNode);
	fireEvent(labelled(root, "Name"), "onFocus");
	assert shows(root, "Focus: name"), "focus shown";
	type(root, "Name", "Grace Hopper");
	fireEvent(labelled(root, "Name"), "onSubmitEditing");
	assert shows(root, "Focus: email"), "return key moved focus to email: " + mockToString(root);
	fireEvent(labelled(root, "Email"), "onSubmitEditing");
	assert shows(root, "Saved Grace Hopper &lt;ada@example.com&gt;") || shows(root, "Saved Grace Hopper <ada@example.com>"), "saved: " + mockToString(root);
	assert shows(root, "Focus: none"), "submit blurred the field";
	assert shows(root, "light theme"), "light by default";
	toggle(root, "Use system theme", false);
	toggle(root, "Dark mode", true);
	assert shows(root, "dark theme"), "manual dark theme";
	assert byAttr(root, "accessibilityRole", "header") !== null, "headers carry the header role";
}
