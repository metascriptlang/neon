import { onCleanup } from "../core/cleanup";
import { RaiseError, createErrorRoute } from "../core/boundary";
import { useContext } from "./context";
import { requestFrame, cancelFrame, frameRequested, frameNow } from "../animation/frame";
import { getVoidAreaContext } from "./voidScope";
import { AreaHub } from "./voidAreaHandle";

interface ClockSubscriber {
	active: () => boolean;
	priority: float64;
	advance: (seconds: float64) => void;
}

interface AreaClock {
	hub: AreaHub | null;
	subscribers: ClockSubscriber[];
	pending: int32;
	generation: int32;
	last: float64;
}

const clocks: AreaClock[] = [];

function anyActive(clock: AreaClock): boolean {
	for (const subscriber of clock.subscribers) {
		if (subscriber.active()) { return true; }
	}
	return false;
}

function cancel(clock: AreaClock): void {
	clock.generation += 1;
	if (clock.pending !== 0) { cancelFrame(clock.pending); clock.pending = 0; }
}

function schedule(clock: AreaClock): void {
	const token = clock.generation;
	clock.pending = requestFrame((now: number): void => {
		// cancelFrame cannot remove callbacks already copied into the due batch.
		if (token !== clock.generation) { return; }
		clock.pending = 0;
		const seconds = Math.max(0.0, now - clock.last) / 1000.0;
		clock.last = now;
		let advanced = false;
		for (const subscriber of clock.subscribers.slice(0)) {
			if (clock.subscribers.indexOf(subscriber) >= 0 && subscriber.active()) {
				subscriber.advance(seconds);
				advanced = true;
			}
		}
		const hub = clock.hub;
		if (advanced && hub !== null) { hub.handle.requestFrame(); }
		if (anyActive(clock)) { schedule(clock); }
	});
}

function wake(clock: AreaClock): void {
	if (!anyActive(clock)) { cancel(clock); return; }
	if (clock.pending !== 0 && frameRequested(clock.pending)) { return; }
	clock.last = frameNow();
	schedule(clock);
}

function clockOf(hub: AreaHub | null): AreaClock {
	for (const clock of clocks) {
		if (clock.hub === hub) { return clock; }
	}
	const clock: AreaClock = { hub, subscribers: [], pending: 0, generation: 0, last: 0.0 };
	clocks.push(clock);
	return clock;
}

function join(clock: AreaClock, priority: float64, active: () => boolean, advance: (seconds: float64) => void): () => void {
	if (!Number.isFinite(priority)) { throw new Error("useFrame: priority must be a finite number"); }
	const subscriber: ClockSubscriber = { active, priority, advance };
	let at = clock.subscribers.length;
	while (at > 0 && clock.subscribers[at - 1].priority > priority) { at -= 1; }
	clock.subscribers.splice(at, 0, subscriber);
	let live = true;
	onCleanup((): void => {
		live = false;
		clock.subscribers.splice(clock.subscribers.indexOf(subscriber), 1);
		if (clock.subscribers.length > 0) { wake(clock); return; }
		cancel(clock);
		clocks.splice(clocks.indexOf(clock), 1);
	});
	return (): void => { if (live) { wake(clock); } };
}

// One clock per Void area: `advance` runs once per frame while `active` holds, with the seconds
// since the previous tick. `advance` only moves state; scene writes belong in an effect, so a
// failure reaches the owner's error boundary instead of the shared frame. Call the returned wake
// after anything that may change `active`.
export function useVoidClock(
	active: () => boolean,
	advance: (seconds: float64) => void,
): () => void {
	const area = useContext(getVoidAreaContext());
	if (area === null) { throw new Error("useVoidClock: mount within Void"); }
	return join(clockOf(area.hub), 0.0, active, advance);
}

interface FrameUser {
	stopped: boolean;
	wake: (() => void) | null;
}

// Lower `priority` runs first and equal priorities run in mount order, as in R3F's subscriber sort;
// R3F's rule that a positive priority takes over rendering has no counterpart, since a Scene3D
// paints as an area layer. Within Void it ticks on that area's clock and keeps the area painting; elsewhere on one clock
// with no area to paint.
export function useFrame(callback: (dt: number, time: number) => void, priority: float64 = 0.0): void {
	const user: FrameUser = { stopped: false, wake: null };
	const raise = createErrorRoute((): void => {
		user.stopped = false;
		(user.wake as () => void)();
	});
	if (raise === null) { throw new Error("useFrame: call it under an owner (a component or a root); the callback lives as long as that owner"); }
	const area = useContext(getVoidAreaContext());
	const clock = clockOf(area === null ? null : area.hub);
	user.wake = join(clock, priority, (): boolean => !user.stopped, (seconds: float64): void => {
		try {
			callback(seconds, clock.last / 1000.0);
		} catch (e) {
			user.stopped = true;
			(raise as RaiseError)(e);
		}
	});
	(user.wake as () => void)();
}
