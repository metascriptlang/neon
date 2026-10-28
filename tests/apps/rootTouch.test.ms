import { RootTouchFixture } from "../../examples/components/rootTouch";
import {
	HostNode, MockNode, mockHost, mockNode, mockToString, render, fireTouch, fireEventWith,
} from "../../src/render/host";
import { neonEvent } from "../../src/render/event";
import { flush } from "../../src/core/runtime";

function labelled(node: MockNode, label: string): MockNode | null {
	for (const attr of node.attrs) {
		const value = attr.isDyn ? attr.dyn() : attr.value;
		if (attr.name === "accessibilityLabel" && value === label) { return node; }
	}
	for (const child of node.children) {
		const found = labelled(child, label);
		if (found !== null) { return found; }
	}
	return null;
}

test "RootTouch fixture keeps native control capture and scroll activation source cases" {
	const root = mockNode("root");
	const dispose = render(RootTouchFixture(), mockHost(), root as unknown as HostNode);
	const captured = labelled(root, "captured-switch");
	const plain = labelled(root, "plain-switch");
	const scrollPress = labelled(root, "scroll-press");
	assert captured !== null && captured.tag === "switch";
	assert plain !== null && plain.tag === "switch" && scrollPress !== null;
	fireTouch(captured as MockNode, "onTouchStart", 10, 20, 1000);
	fireTouch(captured as MockNode, "onTouchEnd", 10, 20, 1020);
	const changed = neonEvent("valuechange");
	changed.value = "true";
	fireEventWith(captured as MockNode, "onValueChange", changed);
	flush();
	assert mockToString(root).indexOf("grants 1 releases 1 captured 1 plain 0") >= 0;
	fireEventWith(plain as MockNode, "onValueChange", changed);
	flush();
	assert mockToString(root).indexOf("grants 1 releases 1 captured 1 plain 1") >= 0;
	assert mockToString(root).indexOf("scrollPress 0 in 0 long 0 out 0") >= 0;
	dispose();
}
