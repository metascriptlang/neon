import { createSignal, accessor, Accessor } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render, mockAreaHub, MockNode } from "../../src/render/host";
import { Void, View } from "../../src/components/primitives";
import { Show, Errored } from "../../src/macros/ui/flow";
import { NeonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/node";
import { Scene2D, Anim, Label } from "../../src/components/scene2d";
import { useManualFrames, setFrameDriver, framePending, requestFrame } from "../../src/animation/frame";
import { useVoidClock } from "../../src/render/voidClock";
import { Host } from "../../src/render/hostTypes";
import { NodeRef, Scene2D as VoidScene2D, animFrames, frameIndex, content, isLive, setFrameDelays } from "../../../void/src/void2d/node";
import { Tile, whiteTile, tile, rgba } from "../../../void/src/void2d/types";

import { Texture, create, close } from "../../../void/src/gpu/texture";
import { imageStyle, imageStyles, ObjectFit } from "../../../void/src/void2d/imageStyle";
import { uniformRadii } from "../../../void/src/void2d/boxStyle";
import { labelTexts, cursorShown } from "../../../void/src/void2d/labelText";

test "Anim JSX shows frame zero and advances on the owned Scene2D clock" {
	const clock = useManualFrames();
	const frames: Tile[] = [whiteTile(4.0, 8.0), whiteTile(12.0, 16.0), whiteTile(20.0, 24.0)];
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Anim frames={frames} fps={10.0} ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		assert nodes.length === 1;
		assert nodes[0].animFrames().frameIndex() === 0;
		assert nodes[0].animFrames().frames[0] === frames[0];
		clock.advance(125);
		assert nodes[0].animFrames().frameIndex() === 1;
		assert nodes[0].animFrames().frames[1] === frames[1];
		assert nodes[0].content().w === 4.0;
	} finally { dispose(); setFrameDriver(null); }
	assert !nodes[0].isLive() && nodes[0].scene.closed;
}

function frames3(): Tile[] {
	return [whiteTile(4.0, 8.0), whiteTile(12.0, 16.0), whiteTile(20.0, 24.0)];
}

test "Anim fps speed paused looping and frame controls retain node identity" {
	const clock = useManualFrames();
	const [fps, setFps] = createSignal<float32>(10.0);
	const [speed, setSpeed] = createSignal<float32>(1.0);
	const [paused, setPaused] = createSignal(false);
	const [looping, setLooping] = createSignal(true);
	const [frame, setFrame] = createSignal<int32>(0);
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Anim frames={frames3()} fps={fps()} speed={speed()} paused={paused()} looping={looping()} frame={frame()}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const node = nodes[0];
		clock.advance(125);
		assert node.animFrames().frameIndex() === 1 && node.animFrames().carryMs === 25.0;
		setPaused(true); flush();
		assert !framePending();
		clock.advance(1000);
		assert node.animFrames().frameIndex() === 1 && node.animFrames().carryMs === 25.0;
		setPaused(false); flush(); clock.advance(50);
		assert node.animFrames().frameIndex() === 1 && node.animFrames().carryMs === 75.0;
		setSpeed(0.0); flush();
		assert !framePending();
		clock.advance(1000); setSpeed(2.0); flush(); clock.advance(25);
		assert node.animFrames().frameIndex() === 2;
		setFps(0.0); flush();
		assert !framePending();
		clock.advance(1000); setFps(20.0); setSpeed(1.0); setFrame(1); flush();
		assert node.animFrames().frameIndex() === 1 && node.animFrames().carryMs === 0.0;
		clock.advance(62.5);
		assert node.animFrames().frameIndex() === 2;
		setLooping(false); flush();
		assert !framePending();
		clock.advance(1000);
		assert node.animFrames().frameIndex() === 2;
		setFrame(0); flush(); clock.advance(62.5);
		assert node.animFrames().frameIndex() === 1;
		clock.advance(62.5);
		assert node.animFrames().frameIndex() === 2 && !framePending();
		setLooping(true); flush(); clock.advance(50);
		assert node.animFrames().frameIndex() === 0 && nodes.length === 1;
	} finally { dispose(); setFrameDriver(null); }
}

test "Anim uneven delays override fps zero and changing delays keeps the shown frame" {
	const clock = useManualFrames();
	const [delays, setDelays] = createSignal<Vec<int32>>([100, 200, 50]);
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Anim frames={frames3()} fps={0.0} frameDelays={delays()}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const node = nodes[0];
		clock.advance(125);
		assert node.animFrames().frameIndex() === 1 && node.animFrames().carryMs === 25.0;
		clock.advance(250);
		assert node.animFrames().frameIndex() === 0 && node.animFrames().carryMs === 25.0;
		clock.advance(125);
		assert node.animFrames().frameIndex() === 1;
		setDelays([50, 100, 200]); flush();
		assert node.animFrames().frameIndex() === 1 && node.animFrames().carryMs === 0.0;
		clock.advance(125);
		assert node.animFrames().frameIndex() === 2 && node.animFrames().carryMs === 25.0;
		setDelays([]); flush();
		assert !framePending();
		clock.advance(1000);
		assert node.animFrames().frameIndex() === 2;
	} finally { dispose(); setFrameDriver(null); }
}

test "Anim frames and delays replace together then empty single and repopulated demand sleep" {
	const clock = useManualFrames();
	const [phase, setPhase] = createSignal<int32>(0);
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Anim frames={phase() === 1 ? [] : phase() === 2 ? [whiteTile(80.0, 40.0)] : frames3()}
			frameDelays={phase() === 1 ? [] : phase() === 2 ? [200] : [100, 200, 50]} fps={10.0}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const node = nodes[0];
		clock.advance(125);
		setPhase(1); flush();
		assert node.animFrames().frameIndex() === -1 && !framePending();
		assert node.content().w === 4.0 && node.content().h === 8.0;
		clock.advance(1000); setPhase(2); flush();
		assert node.animFrames().frameIndex() === 0 && !framePending();
		assert node.animFrames().frames[0].w === 80.0;
		clock.advance(1000); setPhase(3); flush(); clock.advance(125);
		assert node.animFrames().frameIndex() === 1 && nodes.length === 1;
	} finally { dispose(); setFrameDriver(null); }
}

test "two Anim nodes share one tick without resetting a healthy sibling on pause" {
	const clock = useManualFrames();
	const [paused, setPaused] = createSignal(false);
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Anim frames={frames3()} fps={10.0} paused={paused()} ref={(node: NodeRef): void => { nodes.push(node); }} />
		<Anim frames={frames3()} fps={10.0} ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		clock.advance(125);
		assert nodes[0].animFrames().clock === 0.125 && nodes[1].animFrames().clock === 0.125;
		// Move the driver clock without delivering the pending frame.
		clock.time += 50;
		setPaused(true); flush();
		clock.advance(25);
		assert nodes[0].animFrames().frameIndex() === 1;
		assert nodes[1].animFrames().frameIndex() === 2;
		assert nodes[1].animFrames().carryMs < 0.001;
		setPaused(false); flush(); clock.advance(125);
		assert nodes[0].animFrames().frameIndex() === 2;
		assert nodes[1].animFrames().frameIndex() === 0;
		assert clock.frames === 3;
	} finally { dispose(); setFrameDriver(null); }
}

test "Scene2D clocks stay independent when one becomes idle and resumes" {
	const clock = useManualFrames();
	const [paused, setPaused] = createSignal(false);
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D><Anim frames={frames3()} fps={10.0} paused={paused()} ref={(node: NodeRef): void => { nodes.push(node); }} /></Scene2D>
		<Scene2D><Anim frames={frames3()} fps={10.0} ref={(node: NodeRef): void => { nodes.push(node); }} /></Scene2D>
	</Void>), mockHost(), root as unknown as HostNode);
	try {
		clock.advance(125); setPaused(true); flush(); clock.advance(1000);
		assert nodes[0].animFrames().clock === 0.125 && nodes[1].animFrames().clock === 1.125;
		setPaused(false); flush(); clock.advance(125);
		assert nodes[0].animFrames().clock === 0.25 && nodes[1].animFrames().clock === 1.25;
		assert nodes[0].scene !== nodes[1].scene;
	} finally { dispose(); setFrameDriver(null); }
}

test "Anim hide and remount cancel old demand and own fresh frame state" {
	const clock = useManualFrames();
	const [shown, setShown] = createSignal(true);
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		{Show({ when: accessor(() => shown()), children: element(
			<Anim frames={frames3()} fps={10.0} ref={(node: NodeRef): void => { nodes.push(node); }} />
		) })}
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		clock.advance(125); setShown(false); flush();
		assert !nodes[0].isLive() && !framePending();
		clock.advance(1000); setShown(true); flush();
		assert nodes.length === 2 && nodes[1].animFrames().frameIndex() === 0;
		clock.advance(125);
		assert nodes[1].animFrames().clock === 0.125;
	} finally { dispose(); setFrameDriver(null); }
}

test "Scene2D disposal inside the already due batch prevents a stale tick" {
	const clock = useManualFrames();
	let stop: (() => void) | null = null;
	requestFrame((time: number): void => { if (stop !== null) { stop(); } });
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Anim frames={frames3()} fps={10.0} ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	stop = dispose;
	try {
		clock.advance(125);
		assert nodes[0].scene.closed && !nodes[0].isLive() && !framePending();
	} finally { dispose(); setFrameDriver(null); }
}

function frameRequests(outer: MockNode): int32 {
	let count: int32 = 0;
	for (const attr of outer.attrs) { if (attr.name === "frameRequested") { count += 1; } }
	return count;
}

test "Anim invalidation belongs to its own area and stops after disposal" {
	const clock = useManualFrames();
	const first = mockNode("first");
	const second = mockNode("second");
	const stopFirst = render(element(<Void><Scene2D><Anim frames={frames3()} fps={10.0} /></Scene2D></Void>),
		mockHost(), first as unknown as HostNode);
	const stopSecond = render(element(<Void><Scene2D><Anim frames={frames3()} fps={0.0} /></Scene2D></Void>),
		mockHost(), second as unknown as HostNode);
	try {
		const beforeFirst = frameRequests(first.children[0]);
		const beforeSecond = frameRequests(second.children[0]);
		clock.advance(125);
		assert frameRequests(first.children[0]) > beforeFirst;
		assert frameRequests(second.children[0]) === beforeSecond;
		stopFirst();
		assert !framePending();
		clock.advance(1000);
		assert frameRequests(second.children[0]) === beforeSecond;
	} finally { stopFirst(); stopSecond(); setFrameDriver(null); }
}


test "Anim snapshots caller frames and delays while borrowing textures and retaining size and image style" {
	const clock = useManualFrames();
	const texture = Texture.create(16, 8, null);
	const other = Texture.create(32, 16, null);
	const frames: Tile[] = [tile(texture, 16.0, 8.0), whiteTile(4.0, 4.0)];
	let delays: Vec<int32> = [100, 200];
	const [changed, setChanged] = createSignal(false);
	const [width, setWidth] = createSignal<float32>(80.0);
	const [gray, setGray] = createSignal(false);
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Anim frames={changed() ? [tile(other, 32.0, 16.0), whiteTile(8.0, 8.0), whiteTile(12.0, 12.0)] : frames}
			frameDelays={changed() ? [50, 100, 200] : delays} fps={10.0} width={width()}
			imageStyle={imageStyle(uniformRadii(3.0), gray(), ObjectFit.Contain)}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const node = nodes[0];
		const style = node.animFrames().imageStyle;
		assert style >= 0 && node.animFrames().frames[0].source.texture === texture;
		frames[0] = whiteTile(99.0, 99.0); delays[0] = 500;
		assert node.animFrames().frames[0].w === 16.0 && node.animFrames().delaysMs[0] === 100;
		clock.advance(125);
		assert node.animFrames().frameIndex() === 1;
		setChanged(true); flush();
		assert node.animFrames().frameIndex() === 0 && node.animFrames().frames.length === 3;
		assert node.animFrames().frames[0].source.texture === other && node.animFrames().delaysMs[0] === 50;
		assert node.content().w === 80.0 && node.content().h === 8.0;
		assert node.animFrames().imageStyle === style && !imageStyles[style].grayscale;
		setWidth(120.0); setGray(true); flush();
		assert node.content().w === 120.0 && node.content().h === 8.0;
		assert node.animFrames().imageStyle === style && imageStyles[style].grayscale;
		assert !texture.closed && !other.closed && nodes.length === 1;
	} finally { dispose(); setFrameDriver(null); }
	assert !texture.closed && !other.closed && !nodes[0].isLive();
	texture.close(); other.close();
}

test "Anim malformed coherent replacement preserves last good state and Errored reset retries" {
	const clock = useManualFrames();
	const [changed, setChanged] = createSignal(false);
	let repaired = false;
	const nodes: NodeRef[] = [];
	const resets: (() => void)[] = [];
	const errors: string[] = [];
	const root = mockNode("root");
	const dispose = render(Errored({
		children: element(<Void><Scene2D><Anim
			frames={changed() ? [whiteTile(32.0, 16.0), whiteTile(8.0, 8.0)] : frames3()}
			frameDelays={changed() && repaired ? [50, 100] : [100, 200, 50]} fps={10.0}
			ref={(node: NodeRef): void => { nodes.push(node); }} /></Scene2D></Void>),
		fallback: (error: Accessor<Error>, reset: () => void): NeonNode => {
			errors.push(error().message); resets.push(reset);
			return element(<Void />);
		},
	}), mockHost(), root as unknown as HostNode);
	try {
		clock.advance(125);
		const node = nodes[0];
		setChanged(true); flush();
		assert errors.length === 1 && errors[0] === "Anim: frameDelays must be empty or match frames";
		assert node.isLive() && node.animFrames().frames.length === 3;
		assert node.animFrames().frameIndex() === 1 && node.animFrames().carryMs === 25.0;
		assert node.animFrames().delaysMs[0] === 100 && node.animFrames().delaysMs[1] === 200;
		repaired = true;
		resets[0](); flush();
		assert nodes.length === 1 && node.animFrames().frames.length === 2;
		assert node.animFrames().delaysMs[0] === 50 && node.animFrames().frameIndex() === 0;
		clock.advance(62.5);
		assert node.animFrames().frameIndex() === 1;
	} finally { dispose(); setFrameDriver(null); }
}

test "Anim validation during a shared frame does not strand another scene callback" {
	const clock = useManualFrames();
	const [bad, setBad] = createSignal(false);
	const errors: string[] = [];
	const nodes: NodeRef[] = [];
	requestFrame((time: number): void => { setBad(true); });
	const root = mockNode("root");
	const stopBad = render(Errored({
		children: element(<Void><Scene2D><Anim frames={frames3()} fps={bad() ? -1.0 : 10.0}
			ref={(node: NodeRef): void => { nodes.push(node); }} /></Scene2D></Void>),
		fallback: (error: Accessor<Error>, reset: () => void): NeonNode => {
			errors.push(error().message); return element(<Void />);
		},
	}), mockHost(), root as unknown as HostNode);
	const healthy = mockNode("healthy");
	const stopHealthy = render(element(<Void><Scene2D><Anim frames={frames3()} fps={10.0}
		ref={(node: NodeRef): void => { nodes.push(node); }} /></Scene2D></Void>), mockHost(), healthy as unknown as HostNode);
	try {
		clock.advance(125);
		assert errors.length === 1 && errors[0] === "Anim: fps must be finite and nonnegative";
		assert nodes[0].animFrames().frameIndex() === 1 && nodes[1].animFrames().frameIndex() === 1;
		clock.advance(125);
		assert nodes[1].animFrames().frameIndex() === 2;
	} finally { stopBad(); stopHealthy(); setFrameDriver(null); }
}

test "Scene2D registers a private area layer and unregisters on hide before scene closure" {
	const clock = useManualFrames();
	const [shown, setShown] = createSignal(true);
	const refs: VoidScene2D[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void>
		{Show({ when: accessor(() => shown()), children: element(<Scene2D
			ref={(scene: VoidScene2D): void => { refs.push(scene); }}>
			<Anim frames={frames3()} fps={10.0} />
		</Scene2D>) })}
	</Void>), mockHost(), root as unknown as HostNode);
	try {
		const area = mockAreaHub(root.children[0]);
		assert area.layers().length === 1;
		setShown(false); flush();
		assert area.layers().length === 0 && refs[0].closed && !framePending();
		setShown(true); flush();
		assert area.layers().length === 1 && refs.length === 2 && !refs[1].closed;
	} finally { dispose(); setFrameDriver(null); }
	assert refs[1].closed;
}

test "two Anim nodes advance the shared label blink only once" {
	const clock = useManualFrames();
	const labels: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Anim frames={frames3()} fps={10.0} />
		<Anim frames={frames3()} fps={10.0} />
		<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)} cursorIndex={0}
			cursorColor={rgba(1.0, 1.0, 1.0, 1.0)} cursorBlinkTime={0.2}
			ref={(node: NodeRef): void => { labels.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const label = labels[0];
		const row = label.scene.payloads[label.id.index];
		clock.advance(125);
		assert labelTexts[row].blinkClock === 0.125 && cursorShown(labelTexts[row]);
		clock.advance(125);
		assert labelTexts[row].blinkClock === 0.25 && !cursorShown(labelTexts[row]);
	} finally { dispose(); setFrameDriver(null); }
}

test "Anim invalid frame speed and delay values refuse before any binder mutates playback" {
	const clock = useManualFrames();
	const [mode, setMode] = createSignal<int32>(0);
	let repaired = false;
	const nodes: NodeRef[] = [];
	const resets: (() => void)[] = [];
	const errors: string[] = [];
	const root = mockNode("root");
	const dispose = render(Errored({
		children: element(<Void><Scene2D><Anim frames={frames3()} fps={10.0}
			frame={mode() === 1 && !repaired ? 3 : 0}
			speed={mode() === 2 && !repaired ? -1.0 : 1.0}
			frameDelays={mode() === 3 && !repaired ? [100, 0, 50] : [100, 200, 50]}
			ref={(node: NodeRef): void => { nodes.push(node); }} /></Scene2D></Void>),
		fallback: (error: Accessor<Error>, reset: () => void): NeonNode => {
			errors.push(error().message); resets.push(reset); return element(<Void />);
		},
	}), mockHost(), root as unknown as HostNode);
	try {
		clock.advance(125);
		for (let next: int32 = 1; next <= 3; next += 1) {
			repaired = false;
			setMode(next); flush();
			assert errors.length === next;
			assert nodes[0].animFrames().frameIndex() === 1 && nodes[0].animFrames().carryMs === 25.0;
			assert nodes[0].animFrames().speed === 1.0 && nodes[0].animFrames().delaysMs[1] === 200;
			repaired = true; resets[next - 1](); flush();
			assert nodes.length === 1 && nodes[0].isLive();
		}
		assert errors[0] === "Anim: frame must index frames";
		assert errors[1] === "Anim: speed must be finite and nonnegative";
		assert errors[2] === "Anim: frameDelays must be positive milliseconds";
	} finally { dispose(); setFrameDriver(null); }
}

test "Anim retained-delay apply refusal retries a shorter clip and controls without changed props" {
	const expand = false;
	const clock = useManualFrames();
	const [changed, setChanged] = createSignal(false);
	const replacement: Tile[] = expand
		? [whiteTile(32.0, 16.0), whiteTile(8.0, 8.0), whiteTile(4.0, 4.0), whiteTile(2.0, 2.0)]
		: [whiteTile(32.0, 16.0), whiteTile(8.0, 8.0)];
	const nodes: NodeRef[] = [];
	const resets: (() => void)[] = [];
	const errors: string[] = [];
	const root = mockNode("root");
	const dispose = render(Errored({
		children: element(<Void><Scene2D><Anim
			frames={changed() ? replacement : frames3()} fps={changed() ? (expand ? 5.0 : 20.0) : 10.0}
			speed={changed() ? (expand ? 0.5 : 2.0) : 1.0} looping={!changed()} paused={changed() && expand}
			frame={changed() ? (expand ? 3 : 1) : 0}
			ref={(node: NodeRef): void => { nodes.push(node); }} /></Scene2D></Void>),
		fallback: (error: Accessor<Error>, reset: () => void): NeonNode => {
			errors.push(error().message); resets.push(reset); return element(<Void />);
		},
	}), mockHost(), root as unknown as HostNode);
	try {
		const node = nodes[0];
		const id = node.id;
		node.setFrameDelays([100, 200, 50]);
		clock.advance(125);
		setChanged(true); flush();
		assert errors.length === 1 && errors[0] === "Anim: retained frameDelays must match replacement frames";
		assert node.isLive() && node.id === id && nodes.length === 1;
		assert node.animFrames().frames.length === 3 && node.animFrames().frames[0] === frames3()[0];
		assert node.animFrames().fps === 10.0 && node.animFrames().speed === 1.0;
		assert node.animFrames().looping && !node.animFrames().paused;
		assert node.animFrames().frameIndex() === 1 && node.animFrames().carryMs === 25.0;
		assert node.animFrames().delaysMs.length === 3 && node.animFrames().delaysMs[1] === 200;
		node.setFrameDelays([]);
		resets[0](); flush();
		assert nodes.length === 1 && node.id === id && node.isLive();
		assert node.animFrames().frames.length === replacement.length;
		assert node.animFrames().frames[0] === replacement[0] && node.animFrames().delaysMs.length === 0;
		assert node.animFrames().fps === (expand ? 5.0 : 20.0) && node.animFrames().speed === (expand ? 0.5 : 2.0);
		assert !node.animFrames().looping && node.animFrames().paused === expand;
		assert node.animFrames().frameIndex() === (expand ? 3 : 1) && node.animFrames().carryMs === 0.0;
		assert !framePending();
	} finally { dispose(); setFrameDriver(null); }
}

test "Anim retained-delay apply refusal retries a longer paused clip and explicit frame" {
	const expand = true;
	const clock = useManualFrames();
	const [changed, setChanged] = createSignal(false);
	const replacement: Tile[] = expand
		? [whiteTile(32.0, 16.0), whiteTile(8.0, 8.0), whiteTile(4.0, 4.0), whiteTile(2.0, 2.0)]
		: [whiteTile(32.0, 16.0), whiteTile(8.0, 8.0)];
	const nodes: NodeRef[] = [];
	const resets: (() => void)[] = [];
	const errors: string[] = [];
	const root = mockNode("root");
	const dispose = render(Errored({
		children: element(<Void><Scene2D><Anim
			frames={changed() ? replacement : frames3()} fps={changed() ? (expand ? 5.0 : 20.0) : 10.0}
			speed={changed() ? (expand ? 0.5 : 2.0) : 1.0} looping={!changed()} paused={changed() && expand}
			frame={changed() ? (expand ? 3 : 1) : 0}
			ref={(node: NodeRef): void => { nodes.push(node); }} /></Scene2D></Void>),
		fallback: (error: Accessor<Error>, reset: () => void): NeonNode => {
			errors.push(error().message); resets.push(reset); return element(<Void />);
		},
	}), mockHost(), root as unknown as HostNode);
	try {
		const node = nodes[0];
		const id = node.id;
		node.setFrameDelays([100, 200, 50]);
		clock.advance(125);
		setChanged(true); flush();
		assert errors.length === 1 && errors[0] === "Anim: retained frameDelays must match replacement frames";
		assert node.isLive() && node.id === id && nodes.length === 1;
		assert node.animFrames().frames.length === 3 && node.animFrames().frames[0] === frames3()[0];
		assert node.animFrames().fps === 10.0 && node.animFrames().speed === 1.0;
		assert node.animFrames().looping && !node.animFrames().paused;
		assert node.animFrames().frameIndex() === 1 && node.animFrames().carryMs === 25.0;
		assert node.animFrames().delaysMs.length === 3 && node.animFrames().delaysMs[1] === 200;
		node.setFrameDelays([]);
		resets[0](); flush();
		assert nodes.length === 1 && node.id === id && node.isLive();
		assert node.animFrames().frames.length === replacement.length;
		assert node.animFrames().frames[0] === replacement[0] && node.animFrames().delaysMs.length === 0;
		assert node.animFrames().fps === (expand ? 5.0 : 20.0) && node.animFrames().speed === (expand ? 0.5 : 2.0);
		assert !node.animFrames().looping && node.animFrames().paused === expand;
		assert node.animFrames().frameIndex() === (expand ? 3 : 1) && node.animFrames().carryMs === 0.0;
		assert !framePending();
	} finally { dispose(); setFrameDriver(null); }
}

test "Scene2D transparent prepare returns when onLayout disposes its owner" {
	const clock = useManualFrames();
	const root = mockNode("root");
	const scenes: VoidScene2D[] = [];
	let layouts: int32 = 0;
	let disposeMount: (() => void) | null = null;
	const dispose = render(element(<Void><Scene2D
		ref={(scene: VoidScene2D): void => { scenes.push(scene); }}>
		<View style={{ width: 40, height: 30 }} onLayout={(event: NeonEvent): void => {
			layouts += 1;
			if (disposeMount !== null) { disposeMount(); }
		}} />
		<Anim frames={frames3()} fps={10.0} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	disposeMount = dispose;
	const area = mockAreaHub(root.children[0]);
	const layer = area.layers()[0];
	try {
		assert scenes[0].clear.a === 0.0 && layouts === 0 && !scenes[0].closed;
		layer.layout(320, 240);
		layer.prepare(320, 240);
		assert layouts === 1 && scenes[0].closed && area.layers().length === 0;
		assert !framePending();
		layer.layout(640, 480);
		layer.prepare(640, 480);
		layer.draw();
		clock.advance(125);
		assert layouts === 1 && !framePending();
	} finally { dispose(); setFrameDriver(null); }
}

test "Scene2D nontransparent prepare skips backdrop when onLayout disposes its owner" {
	const clock = useManualFrames();
	const root = mockNode("root");
	const scenes: VoidScene2D[] = [];
	let layouts: int32 = 0;
	let disposeMount: (() => void) | null = null;
	const dispose = render(element(<Void><Scene2D clear={rgba(0.25, 0.5, 0.75, 1.0)}
		ref={(scene: VoidScene2D): void => { scenes.push(scene); }}>
		<View style={{ width: 40, height: 30 }} onLayout={(event: NeonEvent): void => {
			layouts += 1;
			if (disposeMount !== null) { disposeMount(); }
		}} />
		<Anim frames={frames3()} fps={10.0} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	disposeMount = dispose;
	const area = mockAreaHub(root.children[0]);
	const layer = area.layers()[0];
	try {
		assert scenes[0].clear.a === 1.0 && layouts === 0 && !scenes[0].closed;
		layer.layout(320, 240);
		layer.prepare(320, 240);
		assert layouts === 1 && scenes[0].closed && area.layers().length === 0;
		assert !framePending();
		layer.layout(640, 480);
		layer.prepare(640, 480);
		layer.draw();
		clock.advance(125);
		assert layouts === 1 && !framePending();
	} finally { dispose(); setFrameDriver(null); }
}

test "Anim and another area clock subscriber in one Void share one tick and one area frame" {
	const clock = useManualFrames();
	const nodes: NodeRef[] = [];
	const dts: number[] = [];
	const root = mockNode("root");
	const framed: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const wake = useVoidClock((): boolean => true, (seconds: float64): void => { dts.push(seconds); });
		wake();
	};
	const dispose = render(element(<Void>
		<Scene2D><Anim frames={frames3()} fps={10.0} ref={(node: NodeRef): void => { nodes.push(node); }} /></Scene2D>
		{framed}
	</Void>), mockHost(), root as unknown as HostNode);
	try {
		const outer = root.children[0];
		const requested = (): int32 => outer.attrs.filter((a) => a.name === "frameRequested").length as int32;
		const before = requested();
		clock.advance(125);
		assert nodes[0].animFrames().frameIndex() === 1 && dts.length === 1, "both advanced";
		assert requested() === before + 1, "one area frame per tick: " + (requested() - before).toString();
		assert clock.frames === 1;
	} finally { dispose(); setFrameDriver(null); }
}
