import { sleepAsync } from "std/core/promise";

const GIVE_UP_AFTER_POLLS: int32 = 3000;

export class Timer {
	due: int32;
	done: boolean = false;

	constructor(due: int32) {
		this.due = due;
	}
}

// Parked on ~/metascript/.inbox/compiler/2026-10-07-new-promise-executor-does-not-lower.md: a delay polls its clock because `new Promise((resolve) => …)` does not lower.
export class Clock {
	now: int32 = 0;
	timers: Timer[] = [];
}

// Parked on ~/metascript/.inbox/compiler/2026-10-07-async-function-nested-in-generic-function.md (sighting 2026-10-16): a generic `async` function that returns a `T` is refused, so each value type below has its own helper.
async function wait(clock: Clock, ms: int32): Promise<void> {
	const timer = new Timer(clock.now + ms);
	clock.timers.push(timer);
	let polls: int32 = 0;
	while (clock.now < timer.due && polls < GIVE_UP_AFTER_POLLS) { await sleepAsync(1); polls += 1; }
	timer.done = true;
}

export async function delay(clock: Clock, ms: int32, value: int32): Promise<int32> {
	await wait(clock, ms);
	return value;
}

export async function delayStr(clock: Clock, ms: int32, value: string): Promise<string> {
	await wait(clock, ms);
	return value;
}

async function quiet(clock: Clock): Promise<void> {
	let waiting = true;
	while (waiting) {
		waiting = false;
		for (const timer of clock.timers) {
			if (timer.due <= clock.now && !timer.done) { waiting = true; }
		}
		if (waiting) { await sleepAsync(1); }
	}
	await sleepAsync(6);
}

export async function advanceTo(clock: Clock, t: int32): Promise<void> {
	while (true) {
		let next = -1;
		for (const timer of clock.timers) {
			if (!timer.done && timer.due > clock.now && timer.due <= t && (next < 0 || timer.due < next)) { next = timer.due; }
		}
		if (next < 0) { break; }
		clock.now = next;
		await quiet(clock);
	}
	clock.now = t;
	await quiet(clock);
}

export async function settle(clock: Clock): Promise<void> {
	await quiet(clock);
}

// A promise that resolves once its gate is opened by the test.
export class Gate {
	open: boolean = false;
}

export async function opened(gate: Gate): Promise<void> {
	let polls: int32 = 0;
	while (!gate.open && polls < GIVE_UP_AFTER_POLLS) { await sleepAsync(1); polls += 1; }
}

export async function gated(gate: Gate, value: int32): Promise<int32> {
	await opened(gate);
	return value;
}

export async function gatedBool(gate: Gate, value: boolean): Promise<boolean> {
	await opened(gate);
	return value;
}

export async function gatedStr(gate: Gate, value: string): Promise<string> {
	await opened(gate);
	return value;
}

export async function rejectedWhenOpen(gate: Gate, failure: Error): Promise<int32> {
	await opened(gate);
	throw failure;
}

export async function release(gate: Gate): Promise<void> {
	gate.open = true;
	await sleepAsync(8);
}
