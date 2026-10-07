import { Motion } from "../../examples/components/motion";
import { useManualFrames, setFrameDriver } from "../../src/animation/index";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, fireEvent, fireEventWith } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { neonEvent } from "../../src/render/event";

function textOf(n: MockNode): string {
	let out = n.text;
	for (const c of n.children) { out += textOf(c); }
	return out;
}

function find(n: MockNode, tag: string, text: string): MockNode | null {
	if (n.tag === tag && textOf(n) === text) { return n; }
	for (const c of n.children) {
		const hit = find(c, tag, text);
		if (hit !== null) { return hit; }
	}
	return null;
}

function holder(root: MockNode, text: string): MockNode {
	const label = find(root, "text", text);
	if (label === null) { throw new Error("no text " + text); }
	return (label as MockNode).parent as MockNode;
}

function scrolling(n: MockNode): MockNode | null {
	for (const e of n.events) { if (e.name === "onScroll") { return n; } }
	for (const c of n.children) {
		const hit = scrolling(c);
		if (hit !== null) { return hit; }
	}
	return null;
}

function styleOf(n: MockNode): Style {
	return n.style as Style;
}

function press(root: MockNode, label: string): void {
	const button = find(root, "pressable", label);
	if (button === null) { throw new Error("no button " + label); }
	fireEvent(button as MockNode, "onPress");
}

test "the motion example: fade, spring, scroll-linked header, toast" {
	const clock = useManualFrames();
	const root: MockNode = mockNode("root");
	render(element(<Motion />), mockHost(), root as unknown as HostNode);
	assert textOf(root).indexOf("fade 1 · spring 0 · scroll 0 · spin off") >= 0, textOf(root).substring(0, 200);

	const box = holder(root, "fade box");
	assert styleOf(box).opacity === 1;
	press(root, "fade");
	clock.step(25);
	const mid = styleOf(box).opacity as number;
	assert mid > 0 && mid < 1, "fading " + mid.toString();
	clock.step(40);
	assert styleOf(box).opacity === 0 && textOf(root).indexOf("fade 0") >= 0, textOf(root).substring(0, 80);

	const card = holder(root, "spring card");
	press(root, "spring");
	let overshoot = false;
	for (let i = 0; i < 200; i += 1) {
		clock.step(1);
		const t = styleOf(card).transform as string;
		const x = parseFloat(t.substring(t.indexOf("(") + 1, t.indexOf("px")));
		if (x > 160.5) { overshoot = true; }
	}
	assert overshoot, "friction 4 overshoots";
	assert styleOf(card).transform === "translateX(160px)" && textOf(root).indexOf("spring 160") >= 0, styleOf(card).transform as string;

	const spinner = holder(root, "spin");
	press(root, "start spin");
	clock.step(10);
	const angle = styleOf(spinner).transform as string;
	assert angle.startsWith("rotate(") && angle !== "rotate(0deg)", angle;
	clock.step(80);
	assert textOf(root).indexOf("spin on") >= 0, "the loop keeps running past one turn";
	press(root, "stop spin");
	const stopped = styleOf(spinner).transform as string;
	clock.step(10);
	assert styleOf(spinner).transform === stopped && textOf(root).indexOf("spin off") >= 0, "stop holds the angle";

	const header = find(root, "text", "Neon motion");
	const headerBox = (header as MockNode).parent as MockNode;
	assert styleOf(headerBox).height === 110;
	const scrollNode = scrolling(root);
	assert scrollNode !== null, "scroll view";
	const e = neonEvent("scroll");
	e.y = 60;
	fireEventWith(scrollNode as MockNode, "onScroll", e);
	assert styleOf(headerBox).height === 83, "header follows scroll " + (styleOf(headerBox).height as number).toString();
	assert textOf(root).indexOf("scroll 60") >= 0;

	press(root, "toast");
	assert textOf(root).indexOf("toast shown") >= 0;
	press(root, "toast");
	clock.step(60);
	assert textOf(root).indexOf("toast shown") < 0, "toast leaves after its exit";
	setFrameDriver(null);
}
