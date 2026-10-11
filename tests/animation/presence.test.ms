import { Presence } from "../../src/animation/presence";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { createSignal } from "../../src/core/signal";
import { Text } from "../../src/components/primitives";

test "Presence fades its child in, keeps it mounted through the exit, then removes it" {
	const clock = useManualFrames();
	const [open, setOpen] = createSignal(false);
	let exited = 0;
	const root: MockNode = mockNode("root");
	render(element(<Presence when={open()} type="slide-up" duration={160} onExited={() => { exited += 1; }}>
		<Text>panel</Text>
	</Presence>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root></root>", mockToString(root);
	setOpen(true);
	assert mockToString(root) === "<root><view><text>panel</text></view></root>", mockToString(root);
	const box = root.children[0];
	assert (box.style as Style).opacity === 0, "enters from transparent";
	clock.step(5);
	const mid = (box.style as Style).opacity as number;
	assert mid > 0 && mid < 1, "fading in " + mid.toString();
	assert ((box.style as Style).transform as string).startsWith("translateY("), (box.style as Style).transform as string;
	clock.runAll();
	assert (box.style as Style).opacity === 1 && (box.style as Style).transform === "translateY(0px)";
	setOpen(false);
	clock.step(3);
	assert mockToString(root) === "<root><view><text>panel</text></view></root>", "still mounted while exiting";
	clock.runAll();
	assert mockToString(root) === "<root></root>" && exited === 1, mockToString(root);
	setFrameDriver(null);
}

test "Presence reversed mid-exit returns without unmounting" {
	const clock = useManualFrames();
	const [open, setOpen] = createSignal(true);
	const root: MockNode = mockNode("root");
	render(element(<Presence when={open()}><Text>x</Text></Presence>), mockHost(), root as unknown as HostNode);
	assert (root.children[0].style as Style).opacity === 1, "starts shown without animating";
	setOpen(false);
	clock.step(2);
	setOpen(true);
	clock.runAll();
	assert mockToString(root) === "<root><view><text>x</text></view></root>" && (root.children[0].style as Style).opacity === 1;
	setFrameDriver(null);
}
