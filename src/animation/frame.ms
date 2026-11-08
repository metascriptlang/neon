import { flush } from "../core/runtime";

export interface FrameDriver {
	now: () => number;
	schedule: (fire: (target: number) => void) => void;
}

interface FrameRequest {
	id: int32;
	callback: (time: number) => void;
	live: boolean;
}

const NATIVE_FRAME_MS = 16;

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
let scheduled = false;
let nextId: int32 = 1;
let generation: int32 = 0;
let lastFrameTime = -Infinity;

function currentDriver(): FrameDriver {
	if (driver === null) { driver = platformDriver(); }
	return driver as FrameDriver;
}

export function setFrameDriver(next: FrameDriver | null): void {
	driver = next;
	pending = [];
	pendingInput = [];
	scheduled = false;
	generation += 1;
	lastFrameTime = -Infinity;
}

export function installFrameDriver(next: FrameDriver): void {
	if (driver === null) { driver = next; }
}

export function frameNow(): number {
	return currentDriver().now();
}

function runFrame(target: number): void {
	const time = Math.max(target, lastFrameTime);
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

function enqueue(into: FrameRequest[], callback: (time: number) => void): int32 {
	const id = nextId;
	nextId += 1;
	into.push({ id, callback, live: true });
	if (!scheduled) {
		scheduled = true;
		const owner = generation;
		currentDriver().schedule((target: number): void => {
			if (owner === generation) { runFrame(target); }
		});
	}
	return id;
}

export function requestFrame(callback: (time: number) => void): int32 {
	return enqueue(pending, callback);
}

export function requestInputFrame(callback: (time: number) => void): int32 {
	return enqueue(pendingInput, callback);
}

export function cancelFrame(id: int32): void {
	for (const request of pendingInput) {
		if (request.id === id) { request.live = false; }
	}
	for (const request of pending) {
		if (request.id === id) { request.live = false; }
	}
}

export function frameRequested(id: int32): boolean {
	for (const request of pendingInput) {
		if (request.id === id) { return request.live; }
	}
	for (const request of pending) {
		if (request.id === id) { return request.live; }
	}
	return false;
}

export function framePending(): boolean {
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

	constructor() {}

	advance(ms: number): void {
		this.time += ms;
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
		while (this.fire !== null && ran < 100000) {
			this.advance(NATIVE_FRAME_MS);
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
	});
	return clock;
}
