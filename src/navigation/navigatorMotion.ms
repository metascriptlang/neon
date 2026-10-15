import { Accessor, Signal, untrack } from "../core/signal";
import { createMemo } from "../core/memo";
import { createRenderEffect } from "../core/effect";
import { Cleanup } from "../core/types";
import { Animated, AnimatedValue, EndResult, Easing } from "../animation/index";
import { Navigation, NavigatorCore, StackAnimation } from "./core";

export const STACK_DURATION = 350;

export class ScreenMotion {
	progress: AnimatedValue = new AnimatedValue(1);
	moving: Signal<boolean> = new Signal<boolean>(false);
	exited: Signal<boolean> = new Signal<boolean>(false);
}

function contains<P>(list: Navigation<P>[], entry: Navigation<P>): boolean {
	for (const item of list) {
		if (item === entry) { return true; }
	}
	return false;
}

export interface MotionPlan<P> {
	list: Navigation<P>[];
	rendered: Navigation<P>[];
	focused: Navigation<P> | null;
	leaving: Navigation<P>[];
	entering: Navigation<P> | null;
	halted: Navigation<P>[];
	epoch: int32;
}

export class NavigatorMotion<P> {
	core: NavigatorCore<P>;
	stacked: boolean;
	motions: Map<string, ScreenMotion> = new Map<string, ScreenMotion>();
	plan: Accessor<MotionPlan<P>>;

	constructor(core: NavigatorCore<P>, stacked: boolean) {
		this.core = core;
		this.stacked = stacked;
		this.plan = createMemo<MotionPlan<P>>(
			(prev: MotionPlan<P> | null): MotionPlan<P> => this.derive(prev, core.entries(), core.index()),
		);
	}

	of(entry: Navigation<P>): ScreenMotion {
		const known = this.motions.get(entry.route.key);
		if (known !== null) { return known as ScreenMotion; }
		const made = new ScreenMotion();
		this.motions.set(entry.route.key, made);
		return made;
	}

	rendered(): Navigation<P>[] {
		return this.plan().rendered;
	}

	isClosing(entry: Navigation<P>): boolean {
		return contains(this.plan().leaving, entry);
	}

	animationOf(entry: Navigation<P>): StackAnimation {
		const options = entry.options();
		const own = options.animation;
		if (own !== null && own !== "default") { return own as StackAnimation; }
		if (!this.stacked) { return "none"; }
		const presentation = options.presentation;
		if (presentation !== null && presentation === "modal") { return "slide_from_bottom"; }
		if (presentation !== null && presentation === "transparentModal") { return "fade"; }
		return "slide_from_right";
	}

	durationOf(entry: Navigation<P>): number {
		const own = entry.options().animationDuration;
		return own === null ? STACK_DURATION : own as number;
	}

	animateIn(entry: Navigation<P>): void {
		const motion = this.of(entry);
		const kind = untrack((): StackAnimation => this.animationOf(entry));
		if (kind === "none") {
			motion.progress.setValue(1);
			return;
		}
		motion.progress.setValue(0);
		motion.moving.set(true);
		this.settleIn(entry);
	}

	settleIn(entry: Navigation<P>): void {
		const motion = this.of(entry);
		const duration = untrack((): number => this.durationOf(entry));
		Animated.timing(motion.progress, { toValue: 1, duration, easing: Easing.out(Easing.cubic) })
			.start((result: EndResult): void => {
				if (result.finished) { motion.moving.set(false); }
			});
	}

	animateOut(entry: Navigation<P>): void {
		const motion = this.of(entry);
		motion.moving.set(true);
		const duration = untrack((): number => this.durationOf(entry));
		Animated.timing(motion.progress, { toValue: 0, duration, easing: Easing.in(Easing.cubic) })
			.start((result: EndResult): void => {
				motion.moving.set(false);
				motion.exited.set(true);
			});
	}

	derive(prev: MotionPlan<P> | null, list: Navigation<P>[], at: int32): MotionPlan<P> {
		const before = prev === null ? [] as Navigation<P>[] : prev.list;
		const focusedBefore = prev === null ? null : prev.focused;
		const focused = at >= 0 && at < list.length ? list[at] : null;
		const epoch = this.core.screenEpoch;
		const candidates: Navigation<P>[] = [];
		const halted: Navigation<P>[] = [];
		let entering: Navigation<P> | null = null;
		if (prev !== null && prev.epoch !== epoch) {
			for (const entry of prev.leaving) { halted.push(entry); }
			for (const entry of before) {
				if (!contains(list, entry)) { halted.push(entry); }
			}
			return { list, rendered: list, focused, leaving: [], entering, halted, epoch };
		}
		if (prev !== null) {
			for (const entry of prev.leaving) { candidates.push(entry); }
		}
		if (!this.stacked) {
			if (focused !== null && focusedBefore !== focused) { entering = focused; }
		} else if (before.length > 0 && list.length > 0) {
			const previousTop = before[before.length - 1];
			const top = list[list.length - 1];
			if (previousTop !== top) {
				if (!contains(list, previousTop) && contains(before, top)) {
					const kind = untrack((): StackAnimation => this.animationOf(previousTop));
					if (kind !== "none") { candidates.push(previousTop); }
				} else if (!contains(before, top)) {
					entering = top;
				}
			}
		}
		const leaving: Navigation<P>[] = [];
		for (const entry of candidates) {
			if (!this.of(entry).exited.get()) { leaving.push(entry); }
		}
		let rendered = list;
		if (leaving.length > 0) {
			rendered = list.slice(0, list.length);
			for (const entry of leaving) {
				if (!contains(rendered, entry)) { rendered.push(entry); }
			}
		}
		return { list, rendered, focused, leaving, entering, halted, epoch };
	}

	run(plan: MotionPlan<P>, prev: MotionPlan<P> | null): void {
		for (const entry of plan.halted) { this.of(entry).progress.stopAnimation(); }
		const applied = prev === null ? [] as Navigation<P>[] : prev.leaving;
		for (const entry of plan.leaving) {
			if (!contains(applied, entry)) { this.animateOut(entry); }
		}
		const entering = plan.entering;
		if (entering !== null) { this.animateIn(entering as Navigation<P>); }
		if (prev !== null) {
			for (const entry of prev.rendered) {
				if (!contains(plan.rendered, entry)) { this.motions.delete(entry.route.key); }
			}
		}
	}
}

export function createNavigatorMotion<P>(
	core: NavigatorCore<P>,
	stacked: boolean,
): NavigatorMotion<P> {
	const motion = new NavigatorMotion<P>(core, stacked);
	createRenderEffect<MotionPlan<P>>(
		(prev: MotionPlan<P> | null): MotionPlan<P> => motion.plan(),
		(plan: MotionPlan<P>, prev: MotionPlan<P> | null): Cleanup | null => {
			motion.run(plan, prev);
			return null;
		},
	);
	return motion;
}
