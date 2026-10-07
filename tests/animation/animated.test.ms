// Ported from RN Libraries/Animated/__tests__/Animated-test.js and TimingAnimation-test.js.

import { Animated, CompositeAnimation } from "../../src/animation/animated";
import { AnimatedValue, ValueState } from "../../src/animation/nodes";
import { TimingAnimation, EndCallback, EndResult } from "../../src/animation/animation";
import { Easing } from "../../src/animation/easing";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { createEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";

class Probe extends CompositeAnimation {
	starts: int32 = 0;
	stops: int32 = 0;
	resets: int32 = 0;
	ends: EndCallback[] = [];

	constructor() { super(); }

	start(callback: EndCallback | null = null): void {
		this.starts += 1;
		if (callback !== null) { this.ends.push(callback as EndCallback); }
	}

	stop(): void { this.stops += 1; }
	reset(): void { this.resets += 1; }

	end(finished: boolean): void {
		this.ends[this.ends.length - 1]({ finished });
	}
}

class Recorder {
	calls: int32 = 0;
	last: boolean = false;
	constructor() {}
	callback(): EndCallback {
		return (result: EndResult): void => {
			this.calls += 1;
			this.last = result.finished;
		};
	}
}

function close(a: number, b: number, eps: number): boolean {
	return Math.abs(a - b) <= eps;
}

test "timing moves the value along its easing, one frame at a time" {
	const clock = useManualFrames();
	const v = new AnimatedValue(0);
	const done = new Recorder();
	Animated.timing(v, { toValue: 100, duration: 160, easing: Easing.linear }).start(done.callback());
	assert v.peek() === 0;
	clock.advance(16);
	assert close(v.peek(), 10, 0.0001), "first frame " + v.peek().toString();
	clock.step(4);
	assert close(v.peek(), 50, 0.0001), "halfway " + v.peek().toString();
	assert done.calls === 0;
	clock.runAll();
	assert v.peek() === 100 && done.calls === 1 && done.last;
	setFrameDriver(null);
}

test "timing defaults to 500 ms of easeInOut and honours delay" {
	const clock = useManualFrames();
	const v = new AnimatedValue(0);
	Animated.timing(v, { toValue: 1, delay: 100 }).start();
	clock.advance(96);
	assert v.peek() === 0, "still waiting " + v.peek().toString();
	clock.advance(16);
	clock.advance(250);
	assert close(v.peek(), Easing.inOut(Easing.ease)(250.0 / 500.0), 0.0001), "eased half " + v.peek().toString();
	clock.runAll();
	assert v.peek() === 1;
	setFrameDriver(null);
}

test "a zero-duration timing lands at once; stop reports finished false" {
	const clock = useManualFrames();
	const v = new AnimatedValue(0);
	const instant = new Recorder();
	Animated.timing(v, { toValue: 5, duration: 0 }).start(instant.callback());
	assert v.peek() === 5 && instant.calls === 1 && instant.last;
	const stopped = new Recorder();
	const a = Animated.timing(v, { toValue: 10, duration: 100 });
	a.start(stopped.callback());
	clock.advance(16);
	a.stop();
	assert stopped.calls === 1 && !stopped.last;
	const at = v.peek();
	clock.runAll();
	assert v.peek() === at, "a stopped animation no longer moves";
	setFrameDriver(null);
}

test "TimingAnimation samples 61 frames for one second, 1 for zero" {
	const a = new TimingAnimation({ toValue: 1, duration: 1000 });
	const frames = a.frames();
	assert frames.length === 61 && frames[60] === 1 && frames[59] < 1;
	const z = new TimingAnimation({ toValue: 1, duration: 0 });
	assert z.frames().length === 1 && z.frames()[0] === 1;
}

test "setValue stops a running animation" {
	const clock = useManualFrames();
	const v = new AnimatedValue(0);
	const done = new Recorder();
	Animated.timing(v, { toValue: 100, duration: 1000 }).start(done.callback());
	clock.step(2);
	v.setValue(7);
	assert done.calls === 1 && !done.last && v.peek() === 7;
	clock.runAll();
	assert v.peek() === 7;
	setFrameDriver(null);
}

test "spring at rest calls back at once" {
	const clock = useManualFrames();
	const v = new AnimatedValue(0);
	const done = new Recorder();
	Animated.spring(v, { toValue: 0, velocity: 0 }).start(done.callback());
	clock.advance(16);
	assert done.calls === 1 && done.last;
	setFrameDriver(null);
}

test "a critically damped spring ends exactly on toValue" {
	const clock = useManualFrames();
	const v = new AnimatedValue(0);
	const seen: number[] = [];
	v.addListener((s: ValueState): void => { seen.push(s.value); });
	Animated.spring(v, { stiffness: 8000, damping: 2000, toValue: 15 }).start();
	clock.runAll();
	const beforeLast = seen[seen.length - 2];
	assert beforeLast !== 15 && close(beforeLast, 15, 0.01), "approach " + beforeLast.toString();
	assert v.peek() === 15;
	setFrameDriver(null);
}

test "an underdamped spring overshoots, then settles; config families are exclusive" {
	const clock = useManualFrames();
	const v = new AnimatedValue(0);
	let peak = 0.0;
	v.addListener((s: ValueState): void => { if (s.value > peak) { peak = s.value; } });
	Animated.spring(v, { toValue: 1, friction: 3, tension: 40 }).start();
	clock.runAll();
	assert peak > 1.05, "overshoot " + peak.toString();
	assert v.peek() === 1;
	let threw = false;
	try { Animated.spring(v, { toValue: 1, friction: 3, stiffness: 10 }).start(); } catch (e) { threw = true; }
	assert threw, "tension/friction with stiffness throws";
	setFrameDriver(null);
}

test "decay follows v0 / (1 - d) * (1 - e^(-(1 - d) t)) and stops when it slows" {
	const clock = useManualFrames();
	const v = new AnimatedValue(10);
	const done = new Recorder();
	Animated.decay(v, { velocity: 1, deceleration: 0.997 }).start(done.callback());
	clock.advance(16);
	const expected = 10 + (1 / (1 - 0.997)) * (1 - Math.exp(-(1 - 0.997) * 16));
	assert close(v.peek(), expected, 0.0001), "first frame " + v.peek().toString();
	clock.runAll();
	assert done.calls === 1 && done.last;
	assert close(v.peek(), 10 + 1 / (1 - 0.997), 40), "settles near the limit " + v.peek().toString();
	setFrameDriver(null);
}

test "sequence: empty, in order, interrupted, stopped, restarted" {
	const empty = new Recorder();
	Animated.sequence([]).start(empty.callback());
	assert empty.calls === 1 && empty.last;

	const a1 = new Probe();
	const a2 = new Probe();
	const cb = new Recorder();
	const seq = Animated.sequence([a1, a2]);
	assert a1.starts === 0 && a2.starts === 0;
	seq.start(cb.callback());
	assert a1.starts === 1 && a2.starts === 0 && cb.calls === 0;
	a1.end(true);
	assert a2.starts === 1 && cb.calls === 0;
	a2.end(true);
	assert cb.calls === 1 && cb.last;

	const b1 = new Probe();
	const b2 = new Probe();
	const interrupted = new Recorder();
	Animated.sequence([b1, b2]).start(interrupted.callback());
	b1.end(false);
	assert b2.starts === 0 && interrupted.calls === 1 && !interrupted.last;

	const c1 = new Probe();
	const c2 = new Probe();
	const stopped = new Recorder();
	const s2 = Animated.sequence([c1, c2]);
	s2.start(stopped.callback());
	s2.stop();
	assert c1.stops === 1 && c2.stops === 0 && stopped.calls === 0;
	c1.end(false);
	assert stopped.calls === 1 && !stopped.last;

	const d1 = new Probe();
	const d2 = new Probe();
	const s3 = Animated.sequence([d1, d2]);
	s3.start();
	d1.end(true);
	s3.stop();
	assert d1.starts === 1 && d2.starts === 1;
	s3.start();
	assert d1.starts === 1 && d2.starts === 2, "resumes from the second";

	const e1 = new Probe();
	const e2 = new Probe();
	const done = new Recorder();
	const s4 = Animated.sequence([e1, e2]);
	s4.start(done.callback());
	e1.end(true);
	e2.end(true);
	assert done.calls === 1;
	s4.start(done.callback());
	assert e1.starts === 2 && e2.starts === 1, "a finished sequence restarts from the first";
}

test "loop: indefinite, three times, once, never, interrupted, stopped" {
	const a = new Probe();
	const cb = new Recorder();
	const forever = Animated.loop(a);
	assert a.starts === 0;
	forever.start(cb.callback());
	assert a.starts === 1 && a.resets === 1 && cb.calls === 0;
	a.end(true);
	assert a.resets === 2 && cb.calls === 0;
	a.end(true);
	a.end(true);
	assert a.resets === 4 && cb.calls === 0;

	const b = new Probe();
	const three = new Recorder();
	Animated.loop(b, { iterations: 3 }).start(three.callback());
	b.end(true);
	b.end(true);
	assert b.resets === 3 && three.calls === 0;
	b.end(true);
	assert b.resets === 3 && three.calls === 1 && three.last;

	const c = new Probe();
	const once = new Recorder();
	Animated.loop(c, { iterations: 1 }).start(once.callback());
	assert c.starts === 1 && once.calls === 0;
	c.end(true);
	assert once.calls === 1 && once.last;

	const d = new Probe();
	const never = new Recorder();
	Animated.loop(d, { iterations: 0 }).start(never.callback());
	assert d.starts === 0 && never.calls === 1 && never.last;

	const e = new Probe();
	const interrupted = new Recorder();
	Animated.loop(e).start(interrupted.callback());
	e.end(true);
	e.end(false);
	assert e.resets === 2 && interrupted.calls === 1 && !interrupted.last;

	const f = new Probe();
	const stopped = new Recorder();
	const l = Animated.loop(f);
	l.start(stopped.callback());
	l.stop();
	assert f.resets === 1 && f.stops === 1;
	f.end(false);
	assert f.resets === 1 && stopped.calls === 1 && !stopped.last;

	const g = new Probe();
	Animated.loop(g, { resetBeforeIteration: false }).start();
	g.end(true);
	g.end(true);
	assert g.resets === 0 && g.starts === 3;

	const h1 = new Probe();
	const h2 = new Probe();
	Animated.loop(Animated.sequence([h1, h2]), { resetBeforeIteration: false }).start();
	h1.end(true);
	h2.end(true);
	assert h1.starts === 2, "the next iteration starts the sequence again";
}

test "parallel: empty, null member, all, stop, stop once" {
	const empty = new Recorder();
	Animated.parallel([]).start(empty.callback());
	assert empty.calls === 1 && empty.last;

	const only = new Probe();
	const withNull = new Recorder();
	Animated.parallel([null, only]).start(withNull.callback());
	assert only.starts === 1;
	only.end(true);
	assert withNull.calls === 1 && withNull.last;

	const a1 = new Probe();
	const a2 = new Probe();
	const cb = new Recorder();
	Animated.parallel([a1, a2]).start(cb.callback());
	assert a1.starts === 1 && a2.starts === 1 && cb.calls === 0;
	a1.end(true);
	assert cb.calls === 0;
	a2.end(true);
	assert cb.calls === 1 && cb.last;

	const b1 = new Probe();
	const b2 = new Probe();
	const stopped = new Recorder();
	const p = Animated.parallel([b1, b2]);
	p.start(stopped.callback());
	p.stop();
	assert b1.stops === 1 && b2.stops === 1 && stopped.calls === 0;
	b1.end(false);
	assert stopped.calls === 0;
	b2.end(false);
	assert stopped.calls === 1 && !stopped.last;

	const c1 = new Probe();
	const c2 = new Probe();
	const c3 = new Probe();
	Animated.parallel([c1, c2, c3]).start();
	c1.end(false);
	assert c1.stops === 0 && c2.stops === 1 && c3.stops === 1;
	c2.end(false);
	c3.end(false);
	assert c1.stops === 0 && c2.stops === 1 && c3.stops === 1;
}

test "delay inside a sequence, and stagger, run to the end" {
	const clock = useManualFrames();
	const a = new Probe();
	const cb = new Recorder();
	Animated.sequence([Animated.delay(1000), a]).start(cb.callback());
	clock.runAll();
	assert a.starts === 1 && cb.calls === 0;
	a.end(true);
	assert cb.calls === 1 && cb.last;

	const staggered = new Recorder();
	Animated.stagger(1000, [Animated.delay(1000), Animated.delay(1000), Animated.delay(1000)]).start(staggered.callback());
	clock.runAll();
	assert staggered.calls === 1 && staggered.last;
	setFrameDriver(null);
}

test "stagger starts each member one interval after the previous" {
	const clock = useManualFrames();
	const a = new AnimatedValue(0);
	const b = new AnimatedValue(0);
	Animated.stagger(100, [
		Animated.timing(a, { toValue: 1, duration: 100, easing: Easing.linear }),
		Animated.timing(b, { toValue: 1, duration: 100, easing: Easing.linear }),
	]).start();
	clock.step(4);
	assert a.peek() > 0 && b.peek() === 0, `a ${a.peek()} b ${b.peek()}`;
	clock.runAll();
	assert a.peek() === 1 && b.peek() === 1;
	setFrameDriver(null);
}

test "event maps NeonEvent fields onto values and calls its listener" {
	const y = new AnimatedValue(0);
	const width = new AnimatedValue(0);
	let heard = 0;
	const handler = Animated.event({ y: y, width: width }, { listener: (e: NeonEvent): void => { heard += 1; } });
	const e = neonEvent("scroll");
	e.y = 42;
	e.width = 300;
	handler(e);
	assert y.peek() === 42 && width.peek() === 300 && heard === 1;
	let second = 0;
	const forked = Animated.forkEvent(handler, (ev: NeonEvent): void => { second += 1; });
	forked(e);
	assert heard === 2 && second === 1;
	const lone = Animated.forkEvent(null, (ev: NeonEvent): void => { second += 1; });
	lone(e);
	assert second === 2;
}

test "tracking: a value follows another through a timing of zero duration" {
	const v1 = new AnimatedValue(0);
	const v2 = new AnimatedValue(0);
	Animated.timing(v2, { toValue: 0, toNode: v1, duration: 0 }).start();
	v1.setValue(42);
	assert v2.peek() === 42;
	v1.setValue(7);
	assert v2.peek() === 7;

	const v3 = new AnimatedValue(0);
	const v4 = new AnimatedValue(0);
	Animated.timing(v4, { toValue: 0, toNode: v3.interpolate({ inputRange: [0, 2], outputRange: [0, 1] }), duration: 0 }).start();
	v3.setValue(42);
	assert v4.peek() === 21;

	const v5 = new AnimatedValue(0);
	const v6 = new AnimatedValue(0);
	Animated.timing(v6, { toValue: 0, toNode: v5, duration: 0 }).start();
	v5.setValue(42);
	Animated.timing(v6, { toValue: 7, duration: 0 }).start();
	v5.setValue(1492);
	assert v6.peek() === 7, "a new animation stops the tracking";

	const v7 = new AnimatedValue(42);
	const v8 = new AnimatedValue(0);
	Animated.timing(v8, { toValue: 0, toNode: v7, duration: 0 }).start();
	assert v8.peek() === 42, "tracking starts at the target's value";
}

test "tracking with a spring follows each change of the target" {
	const clock = useManualFrames();
	const target = new AnimatedValue(0);
	const follower = new AnimatedValue(0);
	Animated.spring(follower, { toValue: 0, toNode: target, tension: 3000, friction: 60 }).start();
	target.setValue(1);
	clock.runAll();
	assert Math.round(follower.peek()) === 1;
	target.setValue(2);
	clock.runAll();
	assert Math.round(follower.peek()) === 2;
	setFrameDriver(null);
}

test "ValueXY animates both axes and reads its layout and transform" {
	const clock = useManualFrames();
	const vec = Animated.ValueXY();
	const opacity = vec.x.interpolate({ inputRange: [0, 42], outputRange: [0.2, 0.8] });
	assert close(opacity.peek(), 0.2, 0.000001);
	vec.setValue({ x: 42, y: 1492 });
	assert close(opacity.peek(), 0.8, 0.000001);
	const layout = vec.getLayout();
	assert layout.left === 42 && layout.top === 1492;
	assert vec.getTranslateTransform() === "translateX(42px) translateY(1492px)", vec.getTranslateTransform();
	Animated.timingXY(vec, { toValue: { x: 0, y: 0 }, duration: 100 }).start();
	clock.runAll();
	assert vec.peek().x === 0 && vec.peek().y === 0;
	setFrameDriver(null);
}

test "listeners: value, derived node, removeAll" {
	const v = new AnimatedValue(0);
	const got: number[] = [];
	const id = v.addListener((s: ValueState): void => { got.push(s.value); });
	v.setValue(42);
	v.setValue(7);
	v.removeListener(id);
	v.setValue(1492);
	assert got.length === 2 && got[0] === 42 && got[1] === 7 && v.peek() === 1492;

	const value1 = new AnimatedValue(40);
	const value2 = new AnimatedValue(50);
	const value3 = new AnimatedValue(0);
	const value4 = Animated.add(value3, Animated.multiply(value1, value2));
	const derived: number[] = [];
	const did = value4.addListener((s: ValueState): void => { derived.push(s.value); });
	value3.setValue(137);
	assert derived.length === 1 && derived[0] === 2137, "derived " + derived.length.toString();
	value1.setValue(0);
	assert derived.length === 2 && derived[1] === 137;
	value4.removeListener(did);
	value1.setValue(40);
	assert derived.length === 2 && value4.peek() === 2137;

	const many = new AnimatedValue(0);
	let count = 0;
	for (let i = 0; i < 4; i += 1) { many.addListener((s: ValueState): void => { count += 1; }); }
	many.setValue(42);
	assert count === 4;
	many.removeAllListeners();
	many.setValue(7);
	assert count === 4;
}

test "diffClamp, modulo, subtract, divide" {
	const inputs = [0, 20, 40, 30, 0, -40, -10, -20, 0];
	const expected = [0, 20, 20, 10, 0, 0, 20, 10, 20];
	const v = new AnimatedValue(0);
	const clamped = Animated.diffClamp(v, 0, 20);
	for (let i = 0; i < inputs.length; i += 1) {
		v.setValue(inputs[i]);
		assert clamped.peek() === expected[i], `diffClamp ${i}: ${clamped.peek()}`;
	}
	const m = new AnimatedValue(-1);
	assert Animated.modulo(m, 3).peek() === 2;
	assert Animated.subtract(Animated.Value(10), m).peek() === 11;
	assert Animated.divide(m, Animated.Value(4)).peek() === -0.25;
	assert Animated.divide(m, Animated.Value(0)).peek() === 0;
}

test "offsets: setOffset, flattenOffset, extractOffset" {
	const v = new AnimatedValue(10);
	v.setOffset(5);
	assert v.peek() === 15;
	v.flattenOffset();
	assert v.peek() === 15 && v.offset === 0 && v.value === 15;
	v.extractOffset();
	assert v.peek() === 15 && v.value === 0 && v.offset === 15;
	v.setValue(1);
	assert v.peek() === 16;
	let stoppedAt = 0.0;
	v.stopAnimation((x: number): void => { stoppedAt = x; });
	assert stoppedAt === 16;
	v.resetAnimation();
	assert v.value === 10;
}

test "a style effect reading a value re-runs once per frame" {
	const clock = useManualFrames();
	const v = new AnimatedValue(0);
	let runs = 0;
	let seen = -1.0;
	createRoot((dispose: () => void): void => {
		createEffect((): void => {
			seen = v.get();
			runs += 1;
		});
	});
	Animated.timing(v, { toValue: 1, duration: 64, easing: Easing.linear }).start();
	clock.advance(16);
	assert runs === 2 && seen === 0.25, `runs ${runs} seen ${seen}`;
	clock.runAll();
	assert seen === 1 && runs === 5, `runs ${runs}`;
	setFrameDriver(null);
}
