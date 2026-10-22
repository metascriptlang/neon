import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { createRenderEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Errored, Show } from "../../src/macros/ui/flow";
import { MockNode, HostNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Host, NeonNode } from "../../src/render/hostTypes";
import { View, Text } from "../../src/components/primitives";
import { useManualFrames, framePending, setFrameDriver } from "../../src/animation/frame";
import { useFrame } from "../../src/render/voidClock";

function framed(fn: (dt: number, time: number) => void): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => { useFrame(fn); };
}

test "useFrame calls back every frame with the seconds since the last one" {
	const clock = useManualFrames();
	const dts: number[] = [];
	const times: number[] = [];
	const dispose = createRoot((dispose: () => void): () => void => {
		useFrame((dt: number, time: number): void => {
			dts.push(dt);
			times.push(time);
		});
		return dispose;
	});
	assert framePending(), "registering asks for a frame";
	clock.advance(16);
	clock.advance(32);
	assert dts.length === 2 && Math.abs(dts[0] - 0.016) < 1e-9 && Math.abs(dts[1] - 0.032) < 1e-9, "dt in seconds: " + dts.join(",");
	assert Math.abs(times[1] - 0.048) < 1e-9, "time in seconds on the frame clock: " + times.join(",");
	assert framePending(), "a live callback keeps the frames coming";
	dispose();
	assert !framePending(), "the last callback leaving stops the loop";
	clock.advance(16);
	assert dts.length === 2, "no call after the owner is gone";
	setFrameDriver(null);
}

test "an unmounted component's useFrame stops the loop" {
	const clock = useManualFrames();
	const [shown, setShown] = createSignal(true);
	let calls = 0;
	const root: MockNode = mockNode("root");
	render(Show({ when: accessor((): boolean => shown()), children: framed((dt: number, time: number): void => { calls += 1; }) }), mockHost(), root as unknown as HostNode);
	clock.step(3);
	assert calls === 3, "called once per frame: " + calls.toString();
	setShown(false);
	flush();
	assert !framePending(), "unmounting stops the loop";
	clock.runAll();
	assert calls === 3, "no call after the unmount: " + calls.toString();
	setFrameDriver(null);
}

test "two callbacks run in one frame, in the order they registered" {
	const clock = useManualFrames();
	const log: string[] = [];
	const dispose = createRoot((dispose: () => void): () => void => {
		useFrame((dt: number, time: number): void => { log.push("a"); });
		useFrame((dt: number, time: number): void => { log.push("b"); });
		return dispose;
	});
	clock.advance(16);
	assert log.join(",") === "a,b", log.join(",");
	assert clock.frames === 1, "one frame served both: " + clock.frames.toString();
	dispose();
	setFrameDriver(null);
}

test "a write inside the callback is flushed before the frame returns" {
	const clock = useManualFrames();
	const seen: int32[] = [];
	const dispose = createRoot((dispose: () => void): () => void => {
		const [n, setN] = createSignal<int32>(0);
		createRenderEffect<int32>((p: int32 | null): int32 => n(), (v: int32, p: int32 | null): Cleanup | null => { seen.push(v); return null; });
		useFrame((dt: number, time: number): void => { setN(n() + 1); });
		return dispose;
	});
	flush();
	clock.advance(16);
	assert seen.join(",") === "0,1", "the effect saw the frame's write within that frame: " + seen.join(",");
	dispose();
	setFrameDriver(null);
}

test "an error inside the callback goes to the Errored around its owner, and reset resumes it" {
	const clock = useManualFrames();
	const failed = new Error("frame 7");
	let fail = false;
	let calls = 0;
	let again: (() => void) | null = null;
	const root: MockNode = mockNode("root");
	render(element(<View>
		<Errored fallback={(err: Accessor<Error>, reset: () => void): NeonNode => {
			again = reset;
			return element(<Text>{err().message}</Text>);
		}}>
			{framed((dt: number, time: number): void => {
				calls += 1;
				if (fail) { throw failed; }
			})}
		</Errored>
	</View>), mockHost(), root as unknown as HostNode);
	clock.advance(16);
	fail = true;
	clock.advance(16);
	flush();
	assert mockToString(root).includes("frame 7"), "the boundary shows the frame error: " + mockToString(root);
	assert !framePending(), "a failed callback lets the loop sleep";
	assert calls === 2, "called until it failed: " + calls.toString();
	fail = false;
	(again as () => void)();
	flush();
	assert framePending(), "reset wakes the loop";
	clock.advance(16);
	assert calls === 3, "reset resumed the callback: " + calls.toString();
	setFrameDriver(null);
}


test "a second error after reset reaches the Errored again" {
	const clock = useManualFrames();
	const first = new Error("first");
	const second = new Error("second");
	let failWith = first;
	let fail = false;
	let again: (() => void) | null = null;
	const root: MockNode = mockNode("root");
	render(element(<View>
		<Errored fallback={(err: Accessor<Error>, reset: () => void): NeonNode => {
			again = reset;
			return element(<Text>{err().message}</Text>);
		}}>
			{framed((dt: number, time: number): void => {
				if (fail) { throw failWith; }
			})}
		</Errored>
	</View>), mockHost(), root as unknown as HostNode);
	clock.advance(16);
	fail = true;
	clock.advance(16);
	flush();
	assert mockToString(root).includes("first"), "the boundary shows the first error: " + mockToString(root);
	failWith = second;
	(again as () => void)();
	flush();
	clock.advance(16);
	flush();
	assert mockToString(root).includes("second"), "the boundary shows the second error: " + mockToString(root);
	setFrameDriver(null);
}

test "useFrame outside any owner throws an Error naming the reason" {
	let message = "";
	try {
		useFrame((dt: number, time: number): void => {});
	} catch (e) {
		message = e.message;
	}
	assert message === "useFrame: call it under an owner (a component or a root); the callback lives as long as that owner", message;
}
