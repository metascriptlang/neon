import { accessor, createSignal, Accessor } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { createRenderEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Host, NeonNode } from "../../src/render/hostTypes";
import { useVoidClock, useFrame } from "../../src/render/voidClock";
import { Void, View } from "../../src/components/primitives";
import { useManualFrames, setFrameDriver, framePending } from "../../src/animation/frame";

function frameRequests(outer: MockNode): int32 {
	let n: int32 = 0;
	for (const a of outer.attrs) {
		if (a.name === "frameRequested") { n += 1; }
	}
	return n;
}

function ticker(active: Accessor<boolean>, log: float64[]): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const wake = useVoidClock(
			(): boolean => active(),
			(seconds: float64): void => { log.push(seconds); },
		);
		wake();
	};
}

test "subscribers of one area advance once per frame by the frame time and sleep when idle" {
	const frames = useManualFrames();
	const [first, setFirst] = createSignal(true);
	const [second, setSecond] = createSignal(false);
	const a: float64[] = [];
	const b: float64[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void>
		{ticker(accessor(() => first()), a)}
		{ticker(accessor(() => second()), b)}
	</Void>), mockHost(), root as unknown as HostNode);
	try {
		const outer = root.children[0];
		assert framePending(), "an active subscriber asks for a frame";
		const before = frameRequests(outer);
		frames.advance(20);
		assert a.length === 1 && Math.abs(a[0] - 0.02) < 1e-9, "dt in seconds from frame time";
		assert b.length === 0, "an inactive subscriber is not advanced";
		assert frameRequests(outer) === before + 1, "one area frame per tick";
		setSecond(true);
		flush();
		frames.advance(10);
		assert a.length === 2 && b.length === 1 && a[1] === b[0], "one shared dt per tick";
		setFirst(false);
		setSecond(false);
		flush();
		frames.advance(10);
		assert !framePending(), "nothing active, nothing scheduled " + a.length.toString() + " " + b.length.toString() + " " + frames.frames.toString();
		const asleep = frameRequests(outer);
		frames.advance(1000);
		assert a.length === 2 && frameRequests(outer) === asleep, "an idle clock neither ticks nor paints";
	} finally { dispose(); setFrameDriver(null); }
}

function wakingTicker(active: Accessor<boolean>, log: float64[]): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const wake = useVoidClock(
			(): boolean => active(),
			(seconds: float64): void => { log.push(seconds); },
		);
		wake();
		createRenderEffect<boolean>(
			(prev: boolean | null): boolean => active(),
			(value: boolean, prev: boolean | null): Cleanup | null => { wake(); return null; },
		);
	};
}

test "wake after sleep starts dt at the wake time" {
	const frames = useManualFrames();
	const [on, setOn] = createSignal(true);
	const log: float64[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void>
		{wakingTicker(accessor(() => on()), log)}
	</Void>), mockHost(), root as unknown as HostNode);
	try {
		frames.advance(16);
		setOn(false);
		flush();
		assert !framePending(), "inactive after wake cancels the frame";
		frames.time += 5000.0;
		setOn(true);
		flush();
		assert framePending();
		frames.advance(8);
		assert log.length === 2 && Math.abs(log[1] - 0.008) < 1e-9, "dt: " + log[1].toString();
	} finally { dispose(); setFrameDriver(null); }
}

test "unmounting the last subscriber cancels its frame and the clock outside Void refuses" {
	const frames = useManualFrames();
	const [shown, setShown] = createSignal(true);
	const log: float64[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void>
		{Show({ when: accessor(() => shown()), children: ticker(accessor(() => true), log) })}
	</Void>), mockHost(), root as unknown as HostNode);
	try {
		assert framePending();
		setShown(false);
		flush();
		assert !framePending(), "no subscriber, no frame";
		frames.advance(16);
		assert log.length === 0;
	} finally { dispose(); setFrameDriver(null); }
	let message = "";
	try {
		render(ticker(accessor(() => true), log), mockHost(), mockNode("bare") as unknown as HostNode);
	} catch (error) { message = error.message; }
	assert message === "useVoidClock: mount within Void", message;
}

test "two areas keep separate clocks" {
	const frames = useManualFrames();
	const [left, setLeft] = createSignal(true);
	const a: float64[] = [];
	const b: float64[] = [];
	const root = mockNode("root");
	const dispose = render(element(<View>
		<Void>{ticker(accessor(() => left()), a)}</Void>
		<Void>{ticker(accessor(() => false), b)}</Void>
	</View>), mockHost(), root as unknown as HostNode);
	try {
		const second = root.children[0].children[1];
		const before = frameRequests(second);
		frames.advance(16);
		frames.advance(16);
		assert a.length === 2 && b.length === 0;
		assert frameRequests(second) === before, "the idle area paints nothing";
	} finally { dispose(); setFrameDriver(null); }
}

function framed(log: float64[]): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		useFrame((dt: number, time: number): void => { log.push(dt); });
	};
}

test "useFrame within Void ticks on the area clock and keeps the area painting while it lives" {
	const frames = useManualFrames();
	const [shown, setShown] = createSignal(true);
	const a: float64[] = [];
	const b: float64[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void>
		{ticker(accessor(() => true), a)}
		{Show({ when: accessor(() => shown()), children: framed(b) })}
	</Void>), mockHost(), root as unknown as HostNode);
	try {
		const outer = root.children[0];
		const before = frameRequests(outer);
		frames.advance(20);
		assert a.length === 1 && b.length === 1 && a[0] === b[0], "one shared dt per tick";
		assert frameRequests(outer) === before + 1, "one area frame per tick for both";
		setShown(false);
		flush();
		frames.advance(10);
		assert b.length === 1, "no call after unmount";
	} finally { dispose(); setFrameDriver(null); }
}

test "a lone useFrame within Void asks its area for a frame every tick and none once it leaves" {
	const frames = useManualFrames();
	const [shown, setShown] = createSignal(true);
	const log: float64[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void>
		{Show({ when: accessor(() => shown()), children: framed(log) })}
	</Void>), mockHost(), root as unknown as HostNode);
	try {
		const outer = root.children[0];
		const before = frameRequests(outer);
		frames.advance(16);
		frames.advance(16);
		assert log.length === 2 && frameRequests(outer) === before + 2, "requests: " + (frameRequests(outer) - before).toString();
		setShown(false);
		flush();
		assert !framePending(), "the area sleeps once the callback leaves";
		const asleep = frameRequests(outer);
		frames.advance(16);
		assert frameRequests(outer) === asleep;
	} finally { dispose(); setFrameDriver(null); }
}
