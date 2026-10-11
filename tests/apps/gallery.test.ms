import { element } from "../../src/macros/ui/element";
import { Host, HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent } from "../../src/render/host";
import { sleepAsync } from "std/core/promise";
import { GalleryApp } from "../../examples/components/gallery";

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

function shows(root: MockNode, text: string): boolean {
	return mockToString(root).indexOf(text) >= 0;
}

test "the gallery presses its button, opens and closes its modal, toggles the status bar and visits the keyboard screen" {
	const host: Host = mockHost();
	const root = mockNode("root");
	render(element(<GalleryApp />), host, root as unknown as HostNode);
	const overlay = (host.overlayRoot as (n: HostNode) => HostNode)(root as unknown as HostNode) as unknown as MockNode;
	assert shows(root, "status: ready"), "mounted: " + mockToString(root).substring(0, 300);
	fireEvent(labelled(root, "Press me"), "onPress");
	assert shows(root, "status: button 1"), "button";
	fireEvent(labelled(root, "Open modal"), "onPress");
	assert shows(overlay, "Modal content"), "modal open: " + mockToString(overlay);
	await sleepAsync(20);
	assert shows(root, "status: modal shown"), "onShow";
	fireEvent(labelled(overlay, "Close modal"), "onPress");
	assert !shows(overlay, "Modal content") && shows(root, "status: modal closed"), "modal closed";
	fireEvent(labelled(root, "Hide status bar"), "onPress");
	assert shows(root, "statusBarHidden=\"true\"") && shows(root, "status: status bar hidden"), "bar hidden";
	fireEvent(labelled(root, "Open keyboard screen"), "onPress");
	assert shows(root, "Back to gallery") && !shows(root, "Open modal"), "keyboard screen";
	fireEvent(labelled(root, "Back to gallery"), "onPress");
	assert shows(root, "Open modal"), "back";
}
