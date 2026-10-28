export enum ReduceMotion {
	System,
	Always,
	Never,
}

export class MotionPolicy {
	reducedMotion: boolean;

	constructor(reducedMotion: boolean = false) {
		this.reducedMotion = reducedMotion;
	}
}

export function shouldReduce(mode: ReduceMotion, policy: MotionPolicy): boolean {
	return match (mode) {
		ReduceMotion.System => policy.reducedMotion,
		ReduceMotion.Always => true,
		ReduceMotion.Never => false,
	};
}
