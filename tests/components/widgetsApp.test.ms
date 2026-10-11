import { Dispose } from "../../src/core/types";
import { HostNode, MockNode, mockNode, mockHost, render, fireEvent } from "../../src/render/host";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";
import { Widgets } from "../../examples/components/widgets";

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

function has(root: MockNode, text: string): boolean {
	return texts(root, []).indexOf(text) >= 0;
}

test "the widgets example mounts every screen on the mock host and reacts to presses" {
	const clock = useManualFrames();
	const root = mockNode("root");
	const dispose: Dispose = render(Widgets(), mockHost(), root as unknown as HostNode);
	assert has(root, "Welcome") && has(root, "Ready"), "the onboarding pages: " + texts(root, []).slice(0, 12).join(",");
	fireEvent(pressable(root, "next") as MockNode, "onPress");
	clock.runAll();
	assert has(root, "status page 2"), "next turns the page: " + texts(root, []).slice(0, 4).join(",");
	fireEvent(pressable(root, "tabs") as MockNode, "onPress");
	assert has(root, "Chats 1") && has(root, "loading Status"), "the tab screen: " + texts(root, []).slice(0, 14).join(",");
	fireEvent(pressable(root, "Calls") as MockNode, "onPress");
	clock.runAll();
	assert has(root, "status tab Calls") && has(root, "Calls 1"), "a tab press: " + texts(root, []).slice(0, 4).join(",");
	fireEvent(pressable(root, "carousel") as MockNode, "onPress");
	assert has(root, "Slide A"), "the carousel";
	fireEvent(pressable(root, "pause") as MockNode, "onPress");
	assert has(root, "status autoplay off") && has(root, "play"), "paused";
	fireEvent(pressable(root, "faq") as MockNode, "onPress");
	fireEvent(pressable(root, "Which platforms?+") as MockNode, "onPress");
	clock.runAll();
	assert has(root, "status faq open 1"), "an accordion section opens: " + texts(root, []).slice(0, 4).join(",");
	fireEvent(pressable(root, "table") as MockNode, "onPress");
	fireEvent(pressable(root, "↑Calories") as MockNode, "onPress");
	assert has(root, "status sorted calories up"), "sorted: " + texts(root, []).slice(0, 4).join(",");
	fireEvent(pressable(root, "Eclair") as MockNode, "onPress");
	assert has(root, "status selected Eclair"), "selected";
	fireEvent(pressable(root, "chips") as MockNode, "onPress");
	assert has(root, "Flexbox"), "the chips";
	dispose();
	setFrameDriver(null);
}
