import { MotionBinding } from "pulse/src/player";
import { MotionTarget } from "pulse/src/target";

export class Demand {
	enter(): void { throw new Error("motion: a demand without enter"); }
	leave(): void { throw new Error("motion: a demand without leave"); }
	flush(): void { throw new Error("motion: a demand without flush"); }
}

export class Watch {
	watched: boolean = false;
	private demands: Demand[] = [];

	attach(demand: Demand): void {
		this.demands.push(demand);
		if (this.watched) { demand.enter(); }
	}

	detach(demand: Demand): void {
		const before = this.demands.length;
		this.demands = this.demands.filter((other: Demand): boolean => other !== demand);
		if (this.watched && this.demands.length < before) { demand.leave(); }
	}

	watch(): void {
		if (this.watched) { return; }
		this.watched = true;
		for (const demand of this.demands) { demand.enter(); }
	}

	unwatch(): void {
		if (!this.watched) { return; }
		this.watched = false;
		for (const demand of this.demands) { demand.leave(); }
	}

	flush(): void {
		for (const demand of this.demands) { demand.flush(); }
	}
}

export class WatchedTarget extends MotionTarget {
	watch: Watch = new Watch();
}

export function watchOf(binding: MotionBinding | null): Watch | null {
	const target = binding === null ? null : (binding.target ?? null);
	if (target === null || !(target instanceof WatchedTarget)) { return null; }
	return (target as WatchedTarget).watch;
}

export class MirrorDemand extends Demand {
	private readers: int32 = 0;
	private watches: Watch[] = [];
	private changed: () => void;
	private catchUp: () => void;

	constructor(changed: () => void, catchUp: () => void) {
		super();
		this.changed = changed;
		this.catchUp = catchUp;
	}

	get watched(): boolean {
		return this.readers > 0;
	}

	follow(bindings: (MotionBinding | null)[]): void {
		for (const binding of bindings) {
			const watch = watchOf(binding);
			if (watch !== null && !this.watches.includes(watch)) {
				this.watches.push(watch);
				watch.attach(this);
			}
		}
	}

	release(): void {
		const watches = this.watches;
		this.watches = [];
		for (const watch of watches) { watch.detach(this); }
	}

	enter(): void {
		this.readers += 1;
		if (this.readers === 1) { this.changed(); }
	}

	leave(): void {
		if (this.readers === 0) { throw new Error("motion: a mirror demand left more often than it entered"); }
		this.readers -= 1;
		if (this.readers === 0) { this.changed(); }
	}

	flush(): void {
		if (this.readers > 0) { this.catchUp(); }
	}
}
