import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, fireEvent, mockHost, mockNode, render } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { framePending, setFrameDriver, useManualFrames } from "../../src/animation/frame";
import { MotionPolicy } from "../../src/motion/policy";
import { LIKED_SCALE, MotionShowcase } from "../../examples/motionShowcase/showcase";

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

function holder(root: MockNode, text: string): Style {
	const label = find(root, "text", text);
	if (label === null) { throw new Error("no text " + text); }
	return ((label as MockNode).parent as MockNode).style as Style;
}

function opacity(root: MockNode, card: string): float64 {
	return holder(root, "card " + card).opacity as float64;
}

function transform(root: MockNode, text: string): string {
	return holder(root, text).transform as string;
}

function pressLike(root: MockNode): void {
	const button = find(root, "pressable", "like");
	if (button === null) { throw new Error("no like button"); }
	fireEvent(button as MockNode, "onPress");
	flush();
}

function mount(policy: MotionPolicy): [MockNode, () => void] {
	const root = mockNode("root");
	const dispose = render(element(<MotionShowcase policy={policy} />), mockHost(), root as unknown as HostNode);
	flush();
	return [root, dispose];
}

test "the cards enter staggered from one document and the like button springs" {
	const frames = useManualFrames();
	const [root, dispose] = mount(new MotionPolicy());
	assert textOf(root).indexOf("entering · not liked") >= 0, textOf(root);
	assert opacity(root, "first") === 0 && transform(root, "card first") === "translateY(24px)";
	assert opacity(root, "second") === 0;

	frames.step(10);
	const first = opacity(root, "first");
	const second = opacity(root, "second");
	assert first > second && second > 0 && first < 1, "staggered: " + first.toString() + " " + second.toString();
	assert Math.abs(first - second - 120.0 / 300.0) < 1e-9, "the second card trails by the stagger";

	frames.runAll();
	assert opacity(root, "first") === 1 && opacity(root, "second") === 1;
	assert transform(root, "card first") === "translateY(0px)" && transform(root, "card second") === "translateY(0px)";
	assert holder(root, "card second").backgroundColor === "rgba(166, 227, 161, 1)",
		holder(root, "card second").backgroundColor as string;
	assert textOf(root).indexOf("entered · not liked") >= 0, textOf(root);
	assert !framePending(), "the finished entrance asks for no frame";

	pressLike(root);
	assert textOf(root).indexOf("liked") >= 0;
	frames.step(4);
	assert transform(root, "like") !== "scale(1)", "springing: " + transform(root, "like");
	frames.runAll();
	assert transform(root, "like") === "scale(" + LIKED_SCALE.toString() + ")", transform(root, "like");
	pressLike(root);
	frames.runAll();
	assert transform(root, "like") === "scale(1)" && textOf(root).indexOf("not liked") >= 0, transform(root, "like");
	dispose();
	setFrameDriver(null);
}

test "reduced motion shows the entered cards at once and jumps the like spring" {
	const frames = useManualFrames();
	const [root, dispose] = mount(new MotionPolicy(true));
	assert opacity(root, "first") === 1 && opacity(root, "second") === 1;
	assert transform(root, "card second") === "translateY(0px)";
	assert textOf(root).indexOf("entered") >= 0, textOf(root);
	pressLike(root);
	assert transform(root, "like") === "scale(" + LIKED_SCALE.toString() + ")", transform(root, "like");
	assert !framePending() && frames.frames === 0, "reduced motion runs no animation frame";
	dispose();
	setFrameDriver(null);
}

test "unmounting mid-entrance stops the frame loop" {
	const frames = useManualFrames();
	const [root, dispose] = mount(new MotionPolicy());
	frames.step(3);
	pressLike(root);
	assert framePending();
	dispose();
	assert !framePending(), "neither the entrance nor the spring asks for a frame after unmount";
	setFrameDriver(null);
}
