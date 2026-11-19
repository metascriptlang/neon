import { Clock } from "pulse/src/clock";
import { MotionPlayer } from "pulse/src/player";

const MARK_EPSILON_MS: float64 = 1e-8;

export type Sleep = (ms: float64, fire: (time: float64) => void) => (() => void);

export function deadlineSleep(source: Clock): Sleep | null {
	const requestAt = source.requestAt;
	if (requestAt === null) { return null; }
	const at = requestAt as (time: float64, callback: (time: float64) => void) => int32;
	return (ms: float64, fire: (time: float64) => void): (() => void) => {
		const id = at(source.now() + ms, fire);
		return (): void => { source.cancel(id); };
	};
}

export class WakeClock {
	clock: Clock;
	wake: (() => float64 | null) | null = null;
	private source: Clock;
	private sleep: Sleep | null;
	private callback: ((time: float64) => void) | null = null;
	private ticket: int32 = 0;
	private frame: int32 = 0;
	private wakeUp: (() => void) | null = null;
	private deferredUntil: float64 = -1;
	private latest: float64 = -Infinity;

	constructor(source: Clock, sleep: Sleep | null) {
		this.source = source;
		this.sleep = sleep;
		this.clock = {
			now: (): float64 => this.now(),
			request: (callback: (time: float64) => void): int32 => this.request(callback),
			cancel: (id: int32): void => { if (id === this.ticket) { this.drop(); } },
		};
	}

	now(): float64 {
		this.latest = Math.max(this.latest, this.source.now());
		return this.latest;
	}

	flush(): void {
		if (this.callback !== null) { this.fire(this.now()); }
	}

	defer(ms: float64): void {
		this.deferredUntil = this.now() + ms;
		this.reschedule();
	}

	undefer(): void {
		this.deferredUntil = -1;
	}

	reschedule(): void {
		if (this.callback === null) { return; }
		this.unschedule();
		this.schedule();
	}

	private request(callback: (time: float64) => void): int32 {
		this.drop();
		this.callback = callback;
		this.ticket += 1;
		this.schedule();
		return this.ticket;
	}

	private waitMs(): float64 | null {
		const wake = this.wake;
		if (wake !== null) { return wake(); }
		if (this.deferredUntil < 0) { return null; }
		const left = this.deferredUntil - this.now();
		if (left <= 0) {
			this.deferredUntil = -1;
			return null;
		}
		return left;
	}

	private schedule(): void {
		const sleep = this.sleep;
		const wait = sleep === null ? null : this.waitMs();
		if (wait === null) {
			this.frame = this.source.request((time: float64): void => {
				this.frame = 0;
				this.fire(time);
			});
			return;
		}
		this.wakeUp = (sleep as Sleep)(wait, (time: float64): void => {
			this.wakeUp = null;
			this.fire(time);
		});
	}

	private unschedule(): void {
		if (this.frame !== 0) {
			this.source.cancel(this.frame);
			this.frame = 0;
		}
		const wakeUp = this.wakeUp;
		if (wakeUp !== null) {
			this.wakeUp = null;
			wakeUp();
		}
	}

	private drop(): void {
		this.unschedule();
		this.callback = null;
	}

	private fire(time: float64): void {
		this.latest = Math.max(this.latest, time);
		const callback = this.callback;
		this.drop();
		if (callback !== null) { callback(this.latest); }
	}
}

export function untilMark(player: MotionPlayer, marks: float64[]): float64 | null {
	const at = player.rawTime;
	const forward = player.timeScale > 0;
	const cycle = player.duration;
	const index = Math.floor(at / cycle);
	const all = marks.concat([0, player.totalDuration, index * cycle, (index + 1) * cycle]);
	let next = forward ? Infinity : -Infinity;
	for (const mark of all) {
		if (Math.abs(mark - at) < MARK_EPSILON_MS) {
			const interior = forward ? mark < player.totalDuration : mark > 0;
			if (interior) { return 1; }
			continue;
		}
		if (forward ? mark > at && mark < next : mark < at && mark > next) {
			next = mark;
		}
	}
	if (!Number.isFinite(next)) { return null; }
	return Math.abs(next - at) / Math.abs(player.timeScale);
}
