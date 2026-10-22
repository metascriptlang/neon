import { flush } from "../core/runtime";
import { RaiseError, createErrorRoute } from "../core/boundary";
import { onCleanup } from "../core/cleanup";

export interface FrameDriver {
	now: () => number;
	schedule: (fire: () => void) => void;
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
			schedule: (fire: () => void): void => {
				requestAnimationFrame((time: number): void => { fire(); });
			},
		};
	}
} else {
	// Not vsync-aligned: WORKAROUND.md N1.
	function platformDriver(): FrameDriver {
		return {
			now: (): number => performance.now(),
			schedule: (fire: () => void): void => {
				setTimeout(fire, NATIVE_FRAME_MS);
			},
		};
	}
}

let driver: FrameDriver | null = null;
let pending: FrameRequest[] = [];
let scheduled = false;
let nextId: int32 = 1;
let generation: int32 = 0;

function currentDriver(): FrameDriver {
	if (driver === null) { driver = platformDriver(); }
	return driver as FrameDriver;
}

export function setFrameDriver(next: FrameDriver | null): void {
	driver = next;
	pending = [];
	scheduled = false;
	generation += 1;
}

export function installFrameDriver(next: FrameDriver): void {
	if (driver === null) { driver = next; }
}

export function frameNow(): number {
	return currentDriver().now();
}

function runFrame(): void {
	scheduled = false;
	const time = currentDriver().now();
	const due = pending;
	pending = [];
	flush((): void => {
		for (const request of due) {
			if (request.live) { request.callback(time); }
		}
	});
}

export function requestFrame(callback: (time: number) => void): int32 {
	const id = nextId;
	nextId += 1;
	pending.push({ id, callback, live: true });
	if (!scheduled) {
		scheduled = true;
		const owner = generation;
		currentDriver().schedule((): void => {
			if (owner === generation) { runFrame(); }
		});
	}
	return id;
}

export function cancelFrame(id: int32): void {
	for (const request of pending) {
		if (request.id === id) { request.live = false; }
	}
}

export function framePending(): boolean {
	for (const request of pending) {
		if (request.live) { return true; }
	}
	return false;
}

interface FrameUser {
	callback: (dt: number, time: number) => void;
	last: number;
	stopped: boolean;
	raise: RaiseError | null;
}

let frameUsers: FrameUser[] = [];
let loopId: int32 = 0;

function loopPending(): boolean {
	for (const request of pending) {
		if (request.id === loopId && request.live) { return true; }
	}
	return false;
}

function wakeLoop(): void {
	for (const user of frameUsers) {
		if (!user.stopped) {
			if (!loopPending()) { loopId = requestFrame(runFrameUsers); }
			return;
		}
	}
	cancelFrame(loopId);
}

function runFrameUsers(time: number): void {
	for (const user of frameUsers.slice(0)) {
		if (user.stopped || frameUsers.indexOf(user) < 0) { continue; }
		const dt = (time - user.last) / 1000;
		user.last = time;
		try {
			user.callback(dt, time / 1000);
		} catch (e) {
			user.stopped = true;
			(user.raise as RaiseError)(e);
		}
	}
	wakeLoop();
}

export function useFrame(callback: (dt: number, time: number) => void): void {
	const user: FrameUser = { callback, last: frameNow(), stopped: false, raise: null };
	user.raise = createErrorRoute((): void => {
		user.stopped = false;
		user.last = frameNow();
		wakeLoop();
	});
	if (user.raise === null) { throw new Error("useFrame: call it under an owner (a component or a root); the callback lives as long as that owner"); }
	frameUsers.push(user);
	onCleanup((): void => {
		const i = frameUsers.indexOf(user);
		if (i >= 0) { frameUsers.splice(i, 1); }
		wakeLoop();
	});
	wakeLoop();
}

export class ManualFrames {
	time: number = 0;
	fire: (() => void) | null = null;
	frames: int32 = 0;

	constructor() {}

	advance(ms: number): void {
		this.time += ms;
		const f = this.fire;
		if (f === null) { return; }
		this.fire = null;
		this.frames += 1;
		(f as () => void)();
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
		schedule: (fire: () => void): void => { clock.fire = fire; },
	});
	return clock;
}
