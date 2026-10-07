import { createRoot } from "../../src/core/owner";
import { HostNode, MockNode, mockNode, mockHost, render, fireEvent } from "../../src/render/host";
import { FlutterLists } from "../../examples/components/flutterLists";

function texts(n: MockNode, out: string[]): string[] {
	if (n.tag === "" && n.text !== "") { out.push(n.text); }
	for (const k of n.children) { texts(k, out); }
	return out;
}

function pressable(n: MockNode, label: string): MockNode | null {
	if (n.tag === "pressable" && texts(n, []).join("") === label) { return n; }
	for (const k of n.children) {
		const hit = pressable(k, label);
		if (hit !== null) { return hit; }
	}
	return null;
}

test "the Flutter lists example mounts every screen on the mock host" {
	const root = mockNode("root");
	createRoot((): void => { render(FlutterLists(), mockHost(), root as unknown as HostNode); });
	assert texts(root, []).indexOf("Mail 1") >= 0, "the mail screen: " + texts(root, []).slice(0, 12).join(",");
	fireEvent(pressable(root, "playlist") as MockNode, "onPress");
	assert texts(root, []).indexOf("status order 1 2 3 4") >= 0, "the playlist screen: " + texts(root, []).slice(0, 12).join(",");
	fireEvent(pressable(root, "photos") as MockNode, "onPress");
	fireEvent(pressable(root, "show masonry") as MockNode, "onPress");
	fireEvent(pressable(root, "header") as MockNode, "onPress");
	assert texts(root, []).indexOf("Collapsing") >= 0, "the header screen";
	fireEvent(pressable(root, "slivers") as MockNode, "onPress");
	assert texts(root, []).indexOf("Albums") >= 0, "the sliver screen: " + texts(root, []).slice(0, 12).join(",");
	fireEvent(pressable(root, "wheel") as MockNode, "onPress");
	assert texts(root, []).indexOf("hour 1") >= 0, "the wheel screen";
}
