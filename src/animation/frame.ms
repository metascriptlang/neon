import { flush } from "../core/runtime";

export interface FrameDriver {
	now: () => number;
	schedule: (fire: (target: number) => void) => void;
	wakeAt?: (time: number, wake: () => void) => (() => void);
}

interface FrameRequest {
	id: int32;
	callback: (time: number) => void;
	live: boolean;
}

interface DeferredFrame {
	time: number;
	request: FrameRequest;
}

const NATIVE_FRAME_MS = 16;
const MAX_TIMER_DELAY_MS = 2147483647;

when (js) {
	extern function requestAnimationFrame(callback: (time: number) => void): number;

	function platformDriver(): FrameDriver {
		return {
			now: (): number => performance.now(),
			schedule: (fire: (target: number) => void): void => {
				requestAnimationFrame((time: number): void => { fire(time); });
			},
		};
	}
} else {
	// Not vsync-aligned: WORKAROUND.md N1.
	function platformDriver(): FrameDriver {
		return {
			now: (): number => performance.now(),
			schedule: (fire: (target: number) => void): void => {
				setTimeout((): void => { fire(performance.now()); }, NATIVE_FRAME_MS);
			},
		};
	}
}

let driver: FrameDriver | null = null;
let pending: FrameRequest[] = [];
let pendingInput: FrameRequest[] = [];
let deferred: DeferredFrame[] = [];
let cancelWake: (() => void) | null = null;
let wakeTime = Infinity;
let scheduled = false;
let nextId: int32 = 1;
let generation: int32 = 0;
let lastFrameTime = -Infinity;
let requestedAt = -Infinity;

function currentDriver(): FrameDriver {
	if (driver === null) { driver = platformDriver(); }
	return driver as FrameDriver;
}

export function setFrameDriver(next: FrameDriver | null): void {
	stopWake();
	deferred = [];
	driver = next;
	pending = [];
	pendingInput = [];
	scheduled = false;
	generation += 1;
	lastFrameTime = -Infinity;
	requestedAt = -Infinity;
}

export function installFrameDriver(next: FrameDriver): void {
	if (driver === null) { driver = next; }
}

export function frameNow(): number {
	return currentDriver().now();
}

function runFrame(target: number): void {
	const time = Math.max(Math.max(target, lastFrameTime), requestedAt);
	lastFrameTime = time;
	const input = pendingInput;
	pendingInput = [];
	try {
		flush((): void => {
			for (const request of input) {
				if (request.live) { request.callback(time); }
			}
		});
	} finally {
		scheduled = false;
	}
	const due = pending;
	pending = [];
	flush((): void => {
		for (const request of due) {
			if (request.live) { request.callback(time); }
		}
	});
}

function newRequest(callback: (time: number) => void): FrameRequest {
	const id = nextId;
	nextId += 1;
	return { id, callback, live: true };
}

function scheduleFrame(): void {
	if (!scheduled) {
		scheduled = true;
		requestedAt = currentDriver().now();
		const owner = generation;
		currentDriver().schedule((target: number): void => {
			if (owner === generation) { runFrame(target); }
		});
	}
}

function enqueue(into: FrameRequest[], callback: (time: number) => void): int32 {
	const request = newRequest(callback);
	into.push(request);
	scheduleFrame();
	return request.id;
}

function stopWake(): void {
	const cancel = cancelWake;
	cancelWake = null;
	wakeTime = Infinity;
	if (cancel !== null) { cancel(); }
}

function armWake(): void {
	let next = Infinity;
	for (const entry of deferred) { next = Math.min(next, entry.time); }
	if (next === wakeTime) { return; }
	stopWake();
	if (next === Infinity) { return; }
	wakeTime = next;
	const owner = generation;
	const wake = (): void => {
		if (owner !== generation) { return; }
		cancelWake = null;
		wakeTime = Infinity;
		const due = deferred;
		deferred = [];
		const now = frameNow();
		let ready = false;
		for (const entry of due) {
			if (entry.time > now) { deferred.push(entry); }
			else { pending.push(entry.request); ready = true; }
		}
		if (ready) { scheduleFrame(); }
		armWake();
	};
	const platformWake = currentDriver().wakeAt;
	if (platformWake !== null) {
		cancelWake = platformWake(next, wake);
	} else {
		const delay = Math.min(MAX_TIMER_DELAY_MS,
			Math.max(0, next - frameNow()));
		const timer = setTimeout(wake, delay);
		cancelWake = (): void => { clearTimeout(timer); };
	}
}

export function requestFrame(callback: (time: number) => void): int32 {
	return enqueue(pending, callback);
}

export function requestFrameAt(time: number, callback: (time: number) => void): int32 {
	if (!Number.isFinite(time)) {
		throw new Error("requestFrameAt: time must be a finite frame-clock timestamp");
	}
	if (time <= frameNow()) { return requestFrame(callback); }
	const request = newRequest(callback);
	deferred.push({ time, request });
	armWake();
	return request.id;
}

export function requestInputFrame(callback: (time: number) => void): int32 {
	return enqueue(pendingInput, callback);
}

export function cancelFrame(id: int32): void {
	for (let i = deferred.length - 1; i >= 0; i -= 1) {
		if (deferred[i].request.id === id) { deferred.splice(i, 1); }
	}
	armWake();
	for (const request of pendingInput) {
		if (request.id === id) { request.live = false; }
	}
	for (const request of pending) {
		if (request.id === id) { request.live = false; }
	}
}

export function frameRequested(id: int32): boolean {
	for (const entry of deferred) {
		if (entry.request.id === id) { return true; }
	}
	for (const request of pendingInput) {
		if (request.id === id) { return request.live; }
	}
	for (const request of pending) {
		if (request.id === id) { return request.live; }
	}
	return false;
}

export function framePending(): boolean {
	if (deferred.length > 0) { return true; }
	for (const request of pendingInput) {
		if (request.live) { return true; }
	}
	for (const request of pending) {
		if (request.live) { return true; }
	}
	return false;
}

export class ManualFrames {
	time: number = 0;
	fire: ((target: number) => void) | null = null;
	frames: int32 = 0;
	wake: (() => void) | null = null;
	wakeTime: number = Infinity;

	constructor() {}

	advance(ms: number): void {
		this.time += ms;
		const wake = this.wake;
		if (wake !== null && this.time >= this.wakeTime) {
			this.wake = null;
			this.wakeTime = Infinity;
			wake();
		}
		const f = this.fire;
		if (f === null) { return; }
		this.fire = null;
		this.frames += 1;
		(f as (target: number) => void)(this.time);
	}

	step(count: int32): void {
		for (let i = 0; i < count; i += 1) { this.advance(NATIVE_FRAME_MS); }
	}

	runAll(): int32 {
		let ran: int32 = 0;
		while ((this.fire !== null || this.wake !== null) && ran < 100000) {
			const delay = this.fire !== null ? NATIVE_FRAME_MS :
				Math.max(NATIVE_FRAME_MS, this.wakeTime - this.time);
			this.advance(delay);
			ran += 1;
		}
		return ran;
	}
}

export function useManualFrames(): ManualFrames {
	const clock = new ManualFrames();
	setFrameDriver({
		now: (): number => clock.time,
		schedule: (fire: (target: number) => void): void => { clock.fire = fire; },
		wakeAt: (time: number, wake: () => void): (() => void) => {
			clock.wakeTime = time;
			clock.wake = wake;
			return (): void => { clock.wake = null; clock.wakeTime = Infinity; };
		},
	});
	return clock;
}
