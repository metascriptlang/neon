import { Accessor, Signal, accessor, untrack } from "../core/signal";
import { createRenderEffect } from "../core/effect";
import { Animated, AnimatedValue, EndResult, Easing } from "../animation/index";
import { Navigation, NavigatorCore, StackAnimation } from "./core";

export const STACK_DURATION = 350;

export class ScreenMotion {
	progress: AnimatedValue = new AnimatedValue(1);
	moving: Signal<boolean> = new Signal<boolean>(false);
}

function contains<P>(list: Navigation<P>[], entry: Navigation<P>): boolean {
	for (const item of list) {
		if (item === entry) { return true; }
	}
	return false;
}

export class NavigatorMotion<P> {
	core: NavigatorCore<P>;
	closing: Signal<Navigation<P>[]> = new Signal<Navigation<P>[]>([]);
	motions: Map<string, ScreenMotion> = new Map<string, ScreenMotion>();
	previous: Navigation<P>[] = [];
	focusedBefore: Navigation<P> | null = null;
	epoch: int32 = 0;

	constructor(core: NavigatorCore<P>) {
		this.core = core;
		this.epoch = core.screenEpoch;
	}

	of(entry: Navigation<P>): ScreenMotion {
		const known = this.motions.get(entry.route.key);
		if (known !== null) { return known as ScreenMotion; }
		const made = new ScreenMotion();
		this.motions.set(entry.route.key, made);
		return made;
	}

	rendered(): Navigation<P>[] {
		const list = this.core.entries();
		const leaving = this.closing.get();
		if (leaving.length === 0) { return list; }
		const all = list.slice(0, list.length);
		for (const entry of leaving) {
			if (!contains(all, entry)) { all.push(entry); }
		}
		return all;
	}

	isClosing(entry: Navigation<P>): boolean {
		return contains(this.closing.get(), entry);
	}

	animationOf(entry: Navigation<P>): StackAnimation {
		const options = entry.options();
		const own = options.animation;
		if (own !== null && own !== "default") { return own as StackAnimation; }
		if (!this.core.isStack()) { return "none"; }
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
		const kind = untrack((): StackAnimation => this.animationOf(entry));
		if (kind === "none") {
			this.motions.delete(entry.route.key);
			return;
		}
		const motion = this.of(entry);
		const leaving = this.closing.peek();
		const next = leaving.slice(0, leaving.length);
		next.push(entry);
		this.closing.set(next);
		motion.moving.set(true);
		const duration = untrack((): number => this.durationOf(entry));
		Animated.timing(motion.progress, { toValue: 0, duration, easing: Easing.in(Easing.cubic) })
			.start((result: EndResult): void => {
				const kept: Navigation<P>[] = [];
				for (const other of this.closing.peek()) {
					if (other !== entry) { kept.push(other); }
				}
				this.closing.set(kept);
				motion.moving.set(false);
				this.motions.delete(entry.route.key);
			});
	}

	snap(list: Navigation<P>[]): void {
		for (const entry of this.closing.peek()) { this.of(entry).progress.stopAnimation(); }
		for (const entry of this.previous) {
			if (!contains(list, entry)) {
				this.of(entry).progress.stopAnimation();
				this.motions.delete(entry.route.key);
			}
		}
		this.closing.set([]);
	}

	changed(list: Navigation<P>[], at: int32): void {
		const before = this.previous;
		const focusedBefore = this.focusedBefore;
		const focused = at >= 0 && at < list.length ? list[at] : null;
		this.previous = list.slice(0, list.length);
		this.focusedBefore = focused;
		if (this.epoch !== this.core.screenEpoch) {
			this.epoch = this.core.screenEpoch;
			this.snap(list);
			return;
		}
		if (!this.core.isStack()) {
			if (focused !== null && focusedBefore !== focused) { this.animateIn(focused as Navigation<P>); }
			return;
		}
		if (before.length === 0 || list.length === 0) { return; }
		const previousTop = before[before.length - 1];
		const top = list[list.length - 1];
		if (previousTop === top) { return; }
		if (!contains(list, previousTop) && contains(before, top)) {
			this.animateOut(previousTop);
			return;
		}
		if (!contains(before, top)) { this.animateIn(top); }
		for (const entry of before) {
			if (!contains(list, entry) && entry !== previousTop) { this.motions.delete(entry.route.key); }
		}
	}
}

export function createNavigatorMotion<P>(core: NavigatorCore<P>): NavigatorMotion<P> {
	const motion = new NavigatorMotion<P>(core);
	createRenderEffect((): void => {
		const list = core.entries();
		const at = core.index();
		untrack((): void => { motion.changed(list, at); });
	});
	return motion;
}
