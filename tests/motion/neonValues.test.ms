import { createRoot } from "../../src/core/owner";
import { createRenderEffect } from "../../src/core/effect";
import { flush } from "../../src/core/runtime";
import { Cleanup, Dispose } from "../../src/core/types";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { Easing } from "pulse/src/easing";
import { setFrameDriver, useManualFrames } from "../../src/animation/frame";
import { timing } from "pulse/src/value";
import {
	animatedEvent,
	createAnimatedValue,
	useValueSignal,
} from "../../src/motion/neonValues";

test "createAnimatedValue needs no owner and its accessor follows the frames" {
	const clock = useManualFrames();
	const [read, value] = createAnimatedValue(0);
	const seen: float64[] = [];
	const dispose = createRoot((d: Dispose): Dispose => {
		createRenderEffect<float64>(
			(prev: float64 | null): float64 => read(),
			(next: float64, prev: float64 | null): Cleanup | null => {
				seen.push(next);
				return null;
			},
		);
		return d;
	});
	let finished = false;
	value.animate(
		timing(1, { duration: 160, easing: Easing.linear }),
		(done: boolean): void => { finished = done; },
	);
	clock.step(5);
	assert Math.abs(read() - 0.5) < 1e-9, "half way " + read().toString();
	clock.runAll();
	assert read() === 1 && finished, "lands on 1";
	assert seen[0] === 0 && seen[seen.length - 1] === 1, seen.join(",");
	dispose();
	setFrameDriver(null);
}

test "useValueSignal reads a derived value and stops with its owner" {
	const [read, value] = createAnimatedValue(0);
	const doubled = value.interpolate({ inputRange: [0, 1], outputRange: [0, 2] });
	let signal: (() => float64) | null = null;
	const dispose = createRoot((d: Dispose): Dispose => {
		signal = useValueSignal(doubled.source());
		return d;
	});
	const tracked = signal as () => float64;
	value.set(0.25);
	flush();
	assert tracked() === 0.5, "follows " + tracked().toString();
	dispose();
	value.set(1);
	flush();
	assert tracked() === 0.5, "unsubscribed with its owner";
	let threw = false;
	try { useValueSignal(doubled.source()); } catch (e) { threw = true; }
	assert threw, "refused outside an owner";
}

test "animatedEvent drives values from a Neon event, then calls the listener" {
	const [scrollRead, scrollY] = createAnimatedValue(0);
	const [widthRead, width] = createAnimatedValue(0);
	let heard = 0;
	const handler = animatedEvent(
		{ y: scrollY, width },
		(e: NeonEvent): void => { heard += 1; },
	);
	const e = neonEvent("scroll");
	e.y = 60;
	e.width = 320;
	handler(e);
	flush();
	assert scrollRead() === 60 && widthRead() === 320 && heard === 1;
}
