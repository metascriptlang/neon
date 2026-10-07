// Flutter widgets/page_view.dart and react-native-pager-view in Neon's vocabulary. A
// PanResponder drags a position measured in pages, and a spring settles it on the page
// PageScrollPhysics picks. Every page is placed by its distance to that position, so a
// looping pager needs no cloned pages and a peeking pager no scroll insets.

import { Accessor, accessor, createSignal, untrack } from "../core/signal";
import { onCleanup } from "../core/cleanup";
import { For } from "../macros/ui/flow";
import { element } from "../macros/ui/element";
import { NeonNode } from "../render/node";
import { NeonEvent } from "../render/event";
import { Style, mergeStyle } from "../render/style";
import { View, Pressable } from "./primitives";
import { PanResponder, PanResponderGestureState } from "./panResponder";
import { Animated, AnimatedValue, CompositeAnimation, Easing, EndResult, ValueState } from "../animation/index";

export type PageOrientation = "horizontal" | "vertical";
export type PageScrollState = "idle" | "dragging" | "settling";

export interface PageRenderItemInfo<T> {
	item: T;
	index: Accessor<number>;
	selected: Accessor<boolean>;
}

// physics.dart ScrollPhysics: minFlingVelocity (kMinFlingVelocity, logical px per second)
// and the default spring, SpringDescription.withDampingRatio(mass: 0.5, stiffness: 100,
// ratio: 1.1).
const MIN_FLING_VELOCITY = 50.0;
const SPRING_MASS = 0.5;
const SPRING_STIFFNESS = 100.0;
const SPRING_DAMPING = 15.556349186104045;
// tabs.dart kTabScrollDuration with Curves.ease, what animateToPage uses for a tab.
const PAGE_ANIMATION_MS = 300;
const DRAG_SLOP = 10;
// An edge drag moves the pages by this share of the finger (WORKAROUND.md W1).
const OVERSCROLL_SHARE = 0.35;

// page_view.dart PageScrollPhysics._getTargetPixels: a fling past the minimum velocity
// rounds half a page towards its direction; otherwise the nearest page wins. Velocity is in
// scroll direction (towards higher pages), logical pixels per second.
export function pageTarget(position: number, velocity: number): number {
	let page = position;
	if (velocity <= -MIN_FLING_VELOCITY) { page -= 0.5; } else if (velocity >= MIN_FLING_VELOCITY) { page += 0.5; }
	return Math.round(page);
}

// The page index a position shows, wrapped into [0, count) when the pager loops.
export function pageIndex(position: number, count: int32, loop: boolean): int32 {
	if (count <= 0) { return 0; }
	const rounded = Math.round(position) as int32;
	if (!loop) { return Math.max(0, Math.min(count - 1, rounded)); }
	const wrapped = rounded % count;
	return wrapped < 0 ? wrapped + count : wrapped;
}

// A page's signed distance in pages from the position; a loop takes the shorter way round.
export function pageDelta(index: number, position: number, count: int32, loop: boolean): number {
	const delta = index - position;
	if (!loop || count <= 0) { return delta; }
	const n = count as number;
	let wrapped = delta - Math.floor(delta / n) * n;
	if (wrapped > n / 2) { wrapped -= n; }
	return wrapped;
}

// Flutter PageController with react-native-pager-view's imperative names beside it. The
// position is in pages and drives every page's placement; read it with `position.get()`.
export class PageController {
	position: AnimatedValue;
	initialPage: number;
	mover: ((page: number, animated: boolean) => void) | null = null;
	reader: (() => number) | null = null;

	constructor(initialPage: number = 0) {
		this.initialPage = initialPage;
		this.position = new AnimatedValue(initialPage);
	}

	// Flutter's `page`: the fractional position, a reactive read.
	page(): number { return this.position.get(); }

	// The position without subscribing.
	peek(): number { return this.position.peek(); }

	// The page last reported by onPageSelected, a reactive read.
	selectedPage(): number {
		const read = this.reader;
		return read === null ? Math.round(this.position.get()) : (read as () => number)();
	}

	animateToPage(index: number): void { this.move(index, true); }
	jumpToPage(index: number): void { this.move(index, false); }
	setPage(index: number): void { this.move(index, true); }
	setPageWithoutAnimation(index: number): void { this.move(index, false); }
	nextPage(): void { this.move(untrack<number>((): number => this.selectedPage()) + 1, true); }
	previousPage(): void { this.move(untrack<number>((): number => this.selectedPage()) - 1, true); }

	private move(index: number, animated: boolean): void {
		const mover = this.mover;
		if (mover === null) { throw "PageController: the controller is not attached to a mounted PageView"; }
		(mover as (page: number, animated: boolean) => void)(index, animated);
	}
}


export function PageView<T>(props: {
	data: Accessor<T[]>;
	renderItem: (info: PageRenderItemInfo<T>) => NeonNode;
	controller?: PageController | null;
	ref?: ((controller: PageController) => void) | null;
	initialPage?: Accessor<number> | null;
	orientation?: Accessor<PageOrientation> | null;
	scrollEnabled?: Accessor<boolean> | null;
	viewportFraction?: Accessor<number> | null;
	loop?: Accessor<boolean> | null;
	pageStyle?: ((delta: number) => Style) | null;
	onPageSelected?: ((index: number) => void) | null;
	onPageScroll?: ((position: number, offset: number) => void) | null;
	onPageScrollStateChanged?: ((state: PageScrollState) => void) | null;
	style?: Accessor<Style> | null;
}): NeonNode {
	const data = props.data;
	const userRender = props.renderItem;
	const { onPageSelected, onPageScroll, onPageScrollStateChanged, pageStyle } = props;
	const orientationProp = props.orientation;
	const enabledProp = props.scrollEnabled;
	const fractionProp = props.viewportFraction;
	const loopProp = props.loop;
	const initialProp = props.initialPage;
	const given = props.controller;
	const initial = initialProp === null ? (given === null ? 0 : (given as PageController).initialPage) : (initialProp as Accessor<number>)();
	const controller = given === null ? new PageController(initial) : given as PageController;
	const position = controller.position;
	if (given === null || initialProp !== null) { position.setValue(initial); }

	const vertical = (): boolean => orientationProp !== null && (orientationProp as Accessor<PageOrientation>)() === "vertical";
	const enabled = (): boolean => enabledProp === null || (enabledProp as Accessor<boolean>)();
	const fraction = (): number => fractionProp === null ? 1 : Math.max(0.05, Math.min(1, (fractionProp as Accessor<number>)()));
	const loops = (): boolean => loopProp !== null && (loopProp as Accessor<boolean>)();
	const count = (): int32 => untrack<T[]>(data).length as int32;

	const [width, setWidth] = createSignal<number>(0);
	const [height, setHeight] = createSignal<number>(0);
	const viewport = (): number => vertical() ? height() : width();
	const extent = (): number => viewport() * fraction();

	let reported: int32 = pageIndex(initial, count(), untrack<boolean>(loops));
	const [selected, setSelected] = createSignal<number>(reported as number);
	controller.reader = (): number => selected();
	let pending: int32 = -1;
	let state: PageScrollState = "idle";
	let motion: CompositeAnimation | null = null;
	let dragStart = 0.0;

	const setState = (next: PageScrollState): void => {
		if (next === state) { return; }
		state = next;
		if (onPageScrollStateChanged !== null) { (onPageScrollStateChanged as (s: PageScrollState) => void)(next); }
	};
	const select = (index: int32): void => {
		if (index === reported) { return; }
		reported = index;
		setSelected(index as number);
		if (onPageSelected !== null) { (onPageSelected as (i: number) => void)(index as number); }
	};

	// page_view.dart onPageChanged: the page under the centre, reported as it changes; a
	// programmatic move reports its target at once and nothing on the way (pager-view).
	const listener = position.addListener((s: ValueState): void => {
		const n = count();
		const loop = untrack<boolean>(loops);
		const at = pageIndex(s.value, n, loop);
		if (pending >= 0) {
			if (at === pending) { pending = -1; }
		} else {
			select(at);
		}
		if (onPageScroll !== null) {
			const base = Math.floor(s.value);
			const page = pageIndex(base, n, loop);
			(onPageScroll as (position: number, offset: number) => void)(page as number, s.value - base);
		}
	});
	const stopMotion = (): void => {
		if (motion !== null) {
			(motion as CompositeAnimation).stop();
			motion = null;
		}
	};
	onCleanup((): void => {
		stopMotion();
		position.removeListener(listener);
		controller.mover = null;
		controller.reader = null;
	});

	const clampTarget = (target: number): number => {
		if (untrack<boolean>(loops)) { return target; }
		return Math.max(0, Math.min((count() - 1) as number, target));
	};
	const settle = (target: number, velocityPages: number): void => {
		stopMotion();
		setState("settling");
		const run = Animated.spring(position, {
			toValue: target, velocity: velocityPages,
			mass: SPRING_MASS, stiffness: SPRING_STIFFNESS, damping: SPRING_DAMPING,
		});
		motion = run;
		run.start((result: EndResult): void => {
			if (motion === run) { motion = null; }
			if (result.finished) {
				position.setValue(target);
				setState("idle");
			}
		});
	};

	controller.mover = (index: number, animated: boolean): void => {
		const n = count();
		if (n <= 0) { return; }
		const loop = untrack<boolean>(loops);
		const from = position.peek();
		let target = Math.round(index);
		if (loop) {
			target = from + pageDelta(pageIndex(index, n, true) as number, from, n, true);
			target = Math.round(target);
		} else {
			target = Math.max(0, Math.min((n - 1) as number, target));
		}
		stopMotion();
		const page = pageIndex(target, n, loop);
		pending = page === pageIndex(from, n, loop) ? -1 : page;
		select(page);
		if (!animated) {
			pending = -1;
			position.setValue(target);
			setState("idle");
			return;
		}
		setState("settling");
		const run = Animated.timing(position, { toValue: target, duration: PAGE_ANIMATION_MS, easing: Easing.ease });
		motion = run;
		run.start((result: EndResult): void => {
			if (motion === run) { motion = null; }
			if (result.finished) {
				pending = -1;
				setState("idle");
			}
		});
	};
	const userRef = props.ref;
	if (userRef !== null) { (userRef as (c: PageController) => void)(controller); }

	const lowerBound = (): number => untrack<boolean>(loops) ? -1e9 : 0;
	const upperBound = (): number => untrack<boolean>(loops) ? 1e9 : (count() - 1) as number;
	const resisted = (raw: number): number => {
		const low = lowerBound();
		const high = upperBound();
		if (raw < low) { return low - (low - raw) * OVERSCROLL_SHARE; }
		if (raw > high) { return high + (raw - high) * OVERSCROLL_SHARE; }
		return raw;
	};

	const pan = PanResponder.create({
		onMoveShouldSetPanResponder: (e: NeonEvent, g: PanResponderGestureState): boolean => {
			if (!untrack<boolean>(enabled) || count() <= 0) { return false; }
			const isVertical = untrack<boolean>(vertical);
			const main = isVertical ? g.dy : g.dx;
			const cross = isVertical ? g.dx : g.dy;
			return Math.abs(main) > DRAG_SLOP && Math.abs(main) > Math.abs(cross);
		},
		onPanResponderGrant: (e: NeonEvent, g: PanResponderGestureState): void => {
			stopMotion();
			pending = -1;
			dragStart = position.peek();
			setState("dragging");
		},
		onPanResponderMove: (e: NeonEvent, g: PanResponderGestureState): void => {
			const length = untrack<number>(extent);
			if (length <= 0) { return; }
			const main = untrack<boolean>(vertical) ? g.dy : g.dx;
			position.setValue(resisted(dragStart - main / length));
		},
		onPanResponderRelease: (e: NeonEvent, g: PanResponderGestureState): void => {
			const length = untrack<number>(extent);
			const velocity = -(untrack<boolean>(vertical) ? g.vy : g.vx) * 1000;
			const at = position.peek();
			const target = clampTarget(pageTarget(at, velocity));
			settle(target, length > 0 ? velocity / length : 0);
		},
		onPanResponderTerminate: (e: NeonEvent, g: PanResponderGestureState): void => {
			settle(clampTarget(Math.round(position.peek())), 0);
		},
	});

	const pageBox = (index: Accessor<number>): Accessor<Style> => accessor((): Style => {
		const size = viewport();
		const length = extent();
		const isVertical = vertical();
		const n = data().length as int32;
		const delta = pageDelta(index(), position.get(), n, loops());
		const shown = size > 0 && Math.abs(delta) * length < (size + length) / 2;
		const inset = (size - length) / 2;
		const offset = inset + delta * length;
		const axis = isVertical ? "translateY" : "translateX";
		const base: Style = isVertical
			? { position: "absolute", left: 0, right: 0, top: 0, height: length }
			: { position: "absolute", top: 0, bottom: 0, left: 0, width: length };
		const placed: Style = { ...base, display: shown ? "flex" : "none", transform: `${axis}(${offset}px)` };
		if (pageStyle === null || !shown) { return placed; }
		const extra = (pageStyle as (d: number) => Style)(delta);
		const extraTransform = extra.transform;
		const merged = mergeStyle(placed, extra);
		return extraTransform === null ? merged : { ...merged, transform: `${axis}(${offset}px) ${extraTransform as string}` };
	});

	const userStyle = props.style;
	const outer = accessor((): Style => mergeStyle({ overflow: "hidden" }, userStyle === null ? {} : (userStyle as Accessor<Style>)()));
	const handlers = pan.panHandlers;
	const pages = For<T>({
		each: data,
		children: (item: T, index: Accessor<number>): NeonNode => View({
			style: pageBox(index),
			children: userRender({ item, index, selected: accessor((): boolean => selected() === index()) }),
		}),
	});
	const layout = (e: NeonEvent): void => {
		if (e.width !== untrack<number>(width)) { setWidth(e.width); }
		if (e.height !== untrack<number>(height)) { setHeight(e.height); }
	};
	return element(<View {...handlers} style={outer} onLayout={layout}>{pages}</View>);
}

export interface PageIndicatorProps {
	count: Accessor<number>;
	page: Accessor<number>;
	onPress?: ((index: number) => void) | null;
	color?: Accessor<string> | null;
	activeColor?: Accessor<string> | null;
	size?: Accessor<number> | null;
	style?: Accessor<Style> | null;
}

const DOT_COLOR = "#9e9e9e";
const DOT_ACTIVE = "#2196f3";
const DOT_SIZE = 8;

// The dots of an onboarding pager (Flutter's smooth_page_indicator, RN's
// react-native-pager-view examples): one dot per page, the selected one wider.
export function PageIndicator(props: PageIndicatorProps): NeonNode {
	const { count, page, onPress } = props;
	const colorProp = props.color;
	const activeProp = props.activeColor;
	const sizeProp = props.size;
	const size = (): number => sizeProp === null ? DOT_SIZE : (sizeProp as Accessor<number>)();
	const indices = accessor((): number[] => {
		const out: number[] = [];
		const n = count() as int32;
		for (let i = 0; i < n; i += 1) { out.push(i as number); }
		return out;
	});
	const dot = (index: number): NeonNode => {
		const active = (): boolean => Math.round(page()) === index;
		const style = accessor((): Style => {
			const s = size();
			return {
				width: active() ? s * 2.5 : s, height: s, borderRadius: s / 2, marginLeft: s / 2, marginRight: s / 2,
				backgroundColor: active()
					? (activeProp === null ? DOT_ACTIVE : (activeProp as Accessor<string>)())
					: (colorProp === null ? DOT_COLOR : (colorProp as Accessor<string>)()),
			};
		});
		const label = (): string => `page ${index + 1} of ${count()}`;
		const press = (e: NeonEvent): void => {
			if (onPress !== null) { (onPress as (i: number) => void)(index); }
		};
		return element(<Pressable style={style} accessibilityLabel={label()} accessibilityRole="button" onPress={press} />);
	};
	const userStyle = props.style;
	return View({
		style: accessor((): Style => mergeStyle({ flexDirection: "row", justifyContent: "center", alignItems: "center", paddingTop: 8, paddingBottom: 8 }, userStyle === null ? {} : (userStyle as Accessor<Style>)())),
		children: For<number>({ each: indices, children: (index: number, at: Accessor<number>): NeonNode => dot(index) }),
	});
}
