export interface Clock {
	now: () => float64;
	request: (callback: (time: float64) => void) => int32;
	cancel: (id: int32) => void;
}

class FrameRequest {
	id: int32;
	callback: (time: float64) => void;
	live: boolean = true;

	constructor(id: int32, callback: (time: float64) => void) {
		this.id = id;
		this.callback = callback;
	}
}

export class ManualClock {
	time: float64 = 0;
	nextId: int32 = 1;
	requests: FrameRequest[] = [];
	firing: FrameRequest[] = [];
	clock: Clock;

	constructor() {
		this.clock = {
			now: (): float64 => this.now(),
			request: (callback: (time: float64) => void): int32 => this.request(callback),
			cancel: (id: int32): void => this.cancel(id),
		};
	}

	now(): float64 {
		return this.time;
	}

	request(callback: (time: float64) => void): int32 {
		const id = this.nextId;
		this.nextId += 1;
		this.requests.push(new FrameRequest(id, callback));
		return id;
	}

	cancel(id: int32): void {
		for (const request of this.requests) {
			if (request.id === id) { request.live = false; }
		}
		for (const request of this.firing) {
			if (request.id === id) { request.live = false; }
		}
	}

	pending(): int32 {
		let count: int32 = 0;
		for (const request of this.requests) {
			if (request.live) { count += 1; }
		}
		return count;
	}

	advance(ms: float64): void {
		if (!Number.isFinite(ms) || ms < 0) { throw new Error("motion: a clock advances by a finite, non-negative time"); }
		this.time += ms;
		this.firing = this.requests;
		this.requests = [];
		for (const request of this.firing) {
			if (request.live) {
				request.live = false;
				request.callback(this.time);
			}
		}
	}
}
