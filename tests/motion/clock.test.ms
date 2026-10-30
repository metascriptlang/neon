import { Clock, ManualClock } from "../../src/motion/clock";

test "a manual clock starts at zero and advances by the given milliseconds" {
	const clock = new ManualClock();
	assert clock.now() === 0;
	clock.advance(16);
	clock.advance(4.5);
	assert clock.now() === 20.5;
}

test "a requested callback fires once, on the next advance, with the new time" {
	const clock = new ManualClock();
	const seen: float64[] = [];
	clock.request((time: float64): void => { seen.push(time); });
	assert seen.length === 0, "nothing fires before time moves";
	clock.advance(10);
	assert seen.length === 1 && seen[0] === 10;
	clock.advance(10);
	assert seen.length === 1, "a callback is one-shot";
}

test "callbacks fire in request order" {
	const clock = new ManualClock();
	const order: int32[] = [];
	clock.request((time: float64): void => { order.push(1); });
	clock.request((time: float64): void => { order.push(2); });
	clock.request((time: float64): void => { order.push(3); });
	clock.advance(1);
	assert order.length === 3 && order[0] === 1 && order[1] === 2 && order[2] === 3;
}

test "a cancelled callback never fires and cancelling twice is harmless" {
	const clock = new ManualClock();
	let fired = 0;
	const id = clock.request((time: float64): void => { fired += 1; });
	clock.cancel(id);
	clock.cancel(id);
	clock.cancel(9999);
	clock.advance(5);
	assert fired === 0;
}

test "a callback cancelled by an earlier callback in the same frame does not fire" {
	const clock = new ManualClock();
	let second = 0;
	let secondId: int32 = 0;
	clock.request((time: float64): void => { clock.cancel(secondId); });
	secondId = clock.request((time: float64): void => { second += 1; });
	clock.advance(5);
	assert second === 0;
}

test "a callback requested during a frame waits for the next frame" {
	const clock = new ManualClock();
	const seen: float64[] = [];
	clock.request((time: float64): void => {
		seen.push(time);
		clock.request((next: float64): void => { seen.push(next); });
	});
	clock.advance(10);
	assert seen.length === 1 && seen[0] === 10;
	assert clock.pending() === 1;
	clock.advance(10);
	assert seen.length === 2 && seen[1] === 20;
	assert clock.pending() === 0;
}

test "request ids are distinct" {
	const clock = new ManualClock();
	const a = clock.request((time: float64): void => {});
	const b = clock.request((time: float64): void => {});
	assert a !== b;
}

test "a negative or non-finite advance fails loud" {
	const clock = new ManualClock();
	let refused = 0;
	try { clock.advance(-1); } catch (e) { if (e.message.startsWith("motion: ")) { refused += 1; } }
	try { clock.advance(NaN); } catch (e) { if (e.message.startsWith("motion: ")) { refused += 1; } }
	try { clock.advance(Infinity); } catch (e) { if (e.message.startsWith("motion: ")) { refused += 1; } }
	assert refused === 3;
	assert clock.now() === 0;
}

function drive(clock: Clock, seen: float64[]): float64 {
	clock.request((time: float64): void => { seen.push(time); });
	return clock.now();
}

test "a ManualClock offers the Clock contract" {
	const clock = new ManualClock();
	const seen: float64[] = [];
	clock.advance(7);
	assert drive(clock.clock, seen) === 7;
	assert clock.pending() === 1;
	clock.advance(3);
	assert clock.pending() === 0;
	assert seen.length === 1 && seen[0] === 10;
	const id = clock.clock.request((time: float64): void => { seen.push(-1); });
	clock.clock.cancel(id);
	clock.advance(1);
	assert seen.length === 1;
}
