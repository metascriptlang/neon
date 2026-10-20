import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockHost, mockNode, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Label, Anim } from "../../src/components/scene2d";
import { useManualFrames, setFrameDriver, framePending, requestFrame } from "../../src/animation/frame";
import { NodeRef, isLive } from "../../../void/src/void2d/node";
import { whiteTile, rgba } from "../../../void/src/void2d/types";
import { labelTexts, cursorShown } from "../../../void/src/void2d/labelText";

test "a standalone Label owns blink demand and reactive cursor controls can stop and restart it" {
	const clock = useManualFrames();
	const [index, setIndex] = createSignal<int32>(0);
	const [period, setPeriod] = createSignal<float32>(0.2);
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)} cursorIndex={index()}
			cursorColor={rgba(1.0, 1.0, 1.0, 1.0)} cursorBlinkTime={period()}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const node = nodes[0];
		const row = node.scene.payloads[node.id.index];
		assert framePending(), "a standalone blinking cursor must request its scene clock";
		clock.advance(250);
		assert labelTexts[row].blinkClock === 0.25 && !cursorShown(labelTexts[row]);
		setIndex(-1); flush();
		assert !framePending() && !cursorShown(labelTexts[row]);
		clock.advance(1000);
		assert labelTexts[row].blinkClock === 0.0;
		setIndex(0); flush();
		assert nodes.length === 1 && nodes[0] === node && framePending();
		clock.advance(250);
		assert labelTexts[row].blinkClock === 0.25 && !cursorShown(labelTexts[row]);
		setPeriod(0.0); flush();
		assert !framePending() && cursorShown(labelTexts[row]);
		clock.advance(1000);
		assert labelTexts[row].blinkClock === 0.0;
		setPeriod(0.2); flush();
		assert framePending();
		clock.advance(250);
		assert labelTexts[row].blinkClock === 0.25 && !cursorShown(labelTexts[row]);
	} finally {
		try {
			dispose();
			assert !nodes[0].isLive() && !framePending();
			clock.advance(1000);
			assert !framePending();
		} finally { setFrameDriver(null); }
	}
}

test "labels without a cursor and steady cursors leave the scene clock idle" {
	const clock = useManualFrames();
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
		<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)} cursorIndex={0}
			cursorColor={rgba(1.0, 1.0, 1.0, 1.0)} cursorBlinkTime={0.0}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		assert !framePending();
		clock.advance(1000);
		for (const node of nodes) { assert labelTexts[node.scene.payloads[node.id.index]].blinkClock === 0.0; }
	} finally {
		try {
			dispose();
			assert !framePending();
			clock.advance(1000);
			assert !framePending();
		} finally { setFrameDriver(null); }
	}
}

test "disposing before an already-due standalone Label callback leaves no demand" {
	const clock = useManualFrames();
	const stops: (() => void)[] = [];
	const nodes: NodeRef[] = [];
	requestFrame((now: number): void => { stops[0](); });
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)} cursorIndex={0}
			cursorColor={rgba(1.0, 1.0, 1.0, 1.0)}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	stops.push(dispose);
	try {
		assert framePending();
		clock.advance(250);
		assert !nodes[0].isLive() && nodes[0].scene.closed && !framePending();
		clock.advance(1000);
		assert !framePending();
	} finally {
		try { dispose(); assert !framePending(); }
		finally { setFrameDriver(null); }
	}
}

test "multiple blinking Labels and an Anim share one scene tick and removal cancels their demand" {
	const clock = useManualFrames();
	const [shown, setShown] = createSignal(true);
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D><Show when={shown()}>
		<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)} cursorIndex={0}
			cursorColor={rgba(1.0, 1.0, 1.0, 1.0)} cursorBlinkTime={0.2}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
		<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)} cursorIndex={0}
			cursorColor={rgba(1.0, 1.0, 1.0, 1.0)} cursorBlinkTime={0.4}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
		<Anim frames={[whiteTile(4.0, 8.0), whiteTile(8.0, 4.0)]} fps={10.0} />
	</Show></Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		clock.advance(250);
		for (const node of nodes) { assert labelTexts[node.scene.payloads[node.id.index]].blinkClock === 0.25; }
		setShown(false); flush();
		assert !framePending() && !nodes[0].isLive() && !nodes[1].isLive();
		clock.advance(1000);
		setShown(true); flush();
		assert nodes.length === 4 && framePending();
		clock.advance(250);
		for (let i = 2; i < 4; i += 1) {
			assert labelTexts[nodes[i].scene.payloads[nodes[i].id.index]].blinkClock === 0.25;
		}
	} finally {
		try {
			dispose();
			assert !framePending();
			clock.advance(1000);
			assert !framePending();
		} finally { setFrameDriver(null); }
	}
}
