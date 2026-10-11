// Provisional frame driver until Animated lands on this branch (WORKAROUND.md F1).

const FRAME_MS = 16;

export type Curve = (t: number) => number;

export function linear(t: number): number {
	return t;
}

export function easeOut(t: number): number {
	const u = 1 - t;
	return 1 - u * u * u;
}

export function easeInOut(t: number): number {
	return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
}

// Flutter Curves.ease is cubic-bezier(0.25, 0.1, 0.25, 1.0); easeInOut stands in for it.
export function ease(t: number): number {
	return easeInOut(t);
}

export class Tween {
	private timer: number = -1;
	private stopped: boolean = false;

	stop(): void {
		this.stopped = true;
		if (this.timer >= 0) {
			clearTimeout(this.timer);
			this.timer = -1;
		}
	}

	isRunning(): boolean {
		return !this.stopped;
	}

	run(from: number, to: number, durationMs: number, curve: Curve, onFrame: (value: number) => void, onDone: () => void): void {
		if (durationMs <= 0) {
			this.stopped = true;
			onFrame(to);
			onDone();
			return;
		}
		const start = performance.now();
		const step = (): void => {
			this.timer = -1;
			if (this.stopped) { return; }
			const t = Math.min(1, (performance.now() - start) / durationMs);
			onFrame(from + (to - from) * curve(t));
			if (t >= 1) {
				this.stopped = true;
				onDone();
				return;
			}
			this.timer = setTimeout(step, FRAME_MS) as number;
		};
		this.timer = setTimeout(step, FRAME_MS) as number;
	}
}

export function tween(from: number, to: number, durationMs: number, curve: Curve, onFrame: (value: number) => void, onDone: () => void): Tween {
	const t = new Tween();
	t.run(from, to, durationMs, curve, onFrame, onDone);
	return t;
}
