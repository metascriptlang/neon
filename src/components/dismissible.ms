// Flutter widgets/dismissible.dart in Neon's vocabulary: a PanResponder drives the
// drag, a tween stands in for its AnimationControllers (WORKAROUND.md F1).

import { Accessor, accessor, createSignal, untrack } from "../core/signal";
import { onCleanup } from "../core/cleanup";
import { NeonNode } from "../render/node";
import { Host, HostNode } from "../render/hostTypes";
import { NeonEvent } from "../render/event";
import { Style, mergeStyle } from "../render/style";
import { View } from "./primitives";
import { element } from "../macros/ui/element";
import { PanResponder, PanResponderGestureState } from "./panResponder";
import { Tween, ease, easeOut, linear, tween } from "./tween";

export type DismissDirection = "horizontal" | "endToStart" | "startToEnd" | "vertical" | "up" | "down" | "none";

// dismissible.dart:18-22.
const RESIZE_HOLD = 0.4;
const MIN_FLING_VELOCITY = 700.0;
const MIN_FLING_VELOCITY_DELTA = 400.0;
const DISMISS_THRESHOLD = 0.4;
const MOVEMENT_MS = 200;
const RESIZE_MS = 300;
const DRAG_SLOP = 10;

export interface DismissibleProps {
	children?: NeonNode | null;
	background?: NeonNode | null;
	secondaryBackground?: NeonNode | null;
	direction?: Accessor<DismissDirection> | null;
	dismissThreshold?: Accessor<number> | null;
	movementDuration?: Accessor<number> | null;
	resizeDuration?: Accessor<number> | null;
	confirmDismiss?: ((direction: DismissDirection) => boolean) | null;
	onResize?: ((sizeFactor: number) => void) | null;
	onUpdate?: ((progress: number, direction: DismissDirection) => void) | null;
	onDismissed?: ((direction: DismissDirection) => void) | null;
	style?: Accessor<Style> | null;
	accessibilityLabel?: Accessor<string> | null;
}

function vertical(direction: DismissDirection): boolean {
	return direction === "vertical" || direction === "up" || direction === "down";
}

function allows(direction: DismissDirection, extent: number): boolean {
	return match (direction) {
		"none" => false,
		"endToStart" => extent <= 0,
		"startToEnd" => extent >= 0,
		"up" => extent <= 0,
		"down" => extent >= 0,
		_ => true,
	};
}

function directionOf(direction: DismissDirection, extent: number): DismissDirection {
	if (vertical(direction)) { return extent > 0 ? "down" : "up"; }
	return extent > 0 ? "startToEnd" : "endToStart";
}

export function Dismissible(props: DismissibleProps): NeonNode {
	const { confirmDismiss, onResize, onUpdate, onDismissed } = props;
	const directionProp = props.direction;
	const thresholdProp = props.dismissThreshold;
	const movementProp = props.movementDuration;
	const resizeProp = props.resizeDuration;
	const direction = (): DismissDirection => directionProp === null ? "horizontal" : (directionProp as Accessor<DismissDirection>)();
	const threshold = (): number => thresholdProp === null ? DISMISS_THRESHOLD : (thresholdProp as Accessor<number>)();
	const movementMs = (): number => movementProp === null ? MOVEMENT_MS : (movementProp as Accessor<number>)();
	const resizeMs = (): number => resizeProp === null ? RESIZE_MS : (resizeProp as Accessor<number>)();

	const [extent, setExtent] = createSignal<number>(0);
	const [sizeFactor, setSizeFactor] = createSignal<number>(1);
	const [resizing, setResizing] = createSignal<boolean>(false);
	let width = 0.0;
	let height = 0.0;
	let dragStart = 0.0;
	let dragging = false;
	let settled = false;
	let motion: Tween | null = null;

	const stopMotion = (): void => {
		if (motion !== null) {
			(motion as Tween).stop();
			motion = null;
		}
	};
	onCleanup(stopMotion);

	const axisLength = (): number => vertical(untrack<DismissDirection>(direction)) ? height : width;
	const report = (value: number): void => {
		setExtent(value);
		if (onUpdate !== null) {
			const length = axisLength();
			const progress = length > 0 ? Math.min(1, Math.abs(value) / length) : 0;
			(onUpdate as (progress: number, direction: DismissDirection) => void)(progress, directionOf(untrack<DismissDirection>(direction), value));
		}
	};

	const finishDismiss = (towards: DismissDirection): void => {
		settled = true;
		if (onDismissed !== null) { (onDismissed as (d: DismissDirection) => void)(towards); }
	};

	const startResize = (towards: DismissDirection): void => {
		const duration = resizeMs();
		if (duration < 0) {
			finishDismiss(towards);
			return;
		}
		setResizing(true);
		stopMotion();
		motion = tween(0, 1, duration, linear, (t: number): void => {
			const local = t <= RESIZE_HOLD ? 0 : (t - RESIZE_HOLD) / (1 - RESIZE_HOLD);
			const factor = 1 - ease(local);
			setSizeFactor(factor);
			if (onResize !== null && t < 1) { (onResize as (f: number) => void)(factor); }
		}, (): void => {
			motion = null;
			finishDismiss(towards);
		});
	};

	const animateTo = (target: number, onDone: () => void): void => {
		stopMotion();
		const from = untrack<number>(extent);
		const length = axisLength();
		const remaining = length > 0 ? Math.abs(target - from) / length : 1;
		motion = tween(from, target, movementMs() * Math.min(1, remaining), easeOut, report, (): void => {
			motion = null;
			onDone();
		});
	};

	const moveCompleted = (): void => {
		const value = untrack<number>(extent);
		const towards = directionOf(untrack<DismissDirection>(direction), value);
		if (threshold() >= 1.0) {
			animateTo(0, (): void => {});
			return;
		}
		const confirmed = confirmDismiss === null ? true : (confirmDismiss as (d: DismissDirection) => boolean)(towards);
		if (!confirmed) {
			animateTo(0, (): void => {});
			return;
		}
		startResize(towards);
	};

	const dismissForward = (): void => {
		const value = untrack<number>(extent);
		const target = (value >= 0 ? 1 : -1) * axisLength();
		animateTo(target, moveCompleted);
	};

	const pan = PanResponder.create({
		onMoveShouldSetPanResponder: (e: NeonEvent, g: PanResponderGestureState): boolean => {
			const dir = untrack<DismissDirection>(direction);
			if (dir === "none" || settled || untrack<boolean>(resizing)) { return false; }
			const main = vertical(dir) ? g.dy : g.dx;
			const cross = vertical(dir) ? g.dx : g.dy;
			if (Math.abs(main) <= DRAG_SLOP || Math.abs(main) <= Math.abs(cross)) { return false; }
			return allows(dir, untrack<number>(extent) + main);
		},
		onPanResponderGrant: (e: NeonEvent, g: PanResponderGestureState): void => {
			stopMotion();
			dragging = true;
			dragStart = untrack<number>(extent);
		},
		onPanResponderMove: (e: NeonEvent, g: PanResponderGestureState): void => {
			const dir = untrack<DismissDirection>(direction);
			let next = dragStart + (vertical(dir) ? g.dy : g.dx);
			if (!allows(dir, next)) { next = 0; }
			report(next);
		},
		onPanResponderRelease: (e: NeonEvent, g: PanResponderGestureState): void => {
			dragging = false;
			const dir = untrack<DismissDirection>(direction);
			const value = untrack<number>(extent);
			const length = axisLength();
			if (value === 0 || length <= 0) {
				animateTo(0, (): void => {});
				return;
			}
			const main = (vertical(dir) ? g.vy : g.vx) * 1000;
			const cross = (vertical(dir) ? g.vx : g.vy) * 1000;
			const fling = Math.abs(main) - Math.abs(cross) >= MIN_FLING_VELOCITY_DELTA && Math.abs(main) >= MIN_FLING_VELOCITY;
			if (fling && allows(dir, main)) {
				if ((main > 0) === (value > 0)) {
					if (threshold() >= 1.0) { animateTo(0, (): void => {}); } else { dismissForward(); }
				} else {
					animateTo(0, (): void => {});
				}
				return;
			}
			if (Math.abs(value) / length > threshold()) { dismissForward(); } else { animateTo(0, (): void => {}); }
		},
		onPanResponderTerminate: (e: NeonEvent, g: PanResponderGestureState): void => {
			dragging = false;
			animateTo(0, (): void => {});
		},
	});

	const contentStyle = accessor((): Style => {
		const value = extent();
		const axis = vertical(direction()) ? "translateY" : "translateX";
		return { transform: `${axis}(${value}px)` };
	});
	const showsBackground = (secondary: boolean): Accessor<Style> => accessor((): Style => {
		const value = extent();
		const hasSecondary = props.secondaryBackground !== null;
		const wantsSecondary = hasSecondary && value < 0;
		const visible = value !== 0 && (secondary ? wantsSecondary : !wantsSecondary);
		return { position: "absolute", left: 0, top: 0, right: 0, bottom: 0, display: visible ? "flex" : "none" };
	});
	const userStyle = props.style;
	const outerStyle = accessor((): Style => {
		const base: Style = { overflow: "hidden", position: "relative" };
		const sized: Style = resizing() ? (vertical(direction()) ? { width: width * sizeFactor(), flexShrink: 0 } : { height: height * sizeFactor(), flexShrink: 0 }) : {};
		return mergeStyle(mergeStyle(base, userStyle === null ? {} : (userStyle as Accessor<Style>)()), sized);
	});
	const background = props.background;
	const secondaryBackground = props.secondaryBackground;
	const children = props.children;
	const handlers = pan.panHandlers;
	const primaryLayer: NeonNode | null = background === null ? null : View({ style: showsBackground(false), children: background });
	const secondaryLayer: NeonNode | null = secondaryBackground === null ? null : View({ style: showsBackground(true), children: secondaryBackground });
	const moving: NeonNode = element(<View {...handlers} style={contentStyle}>{children}</View>);
	return View({
		style: outerStyle,
		accessibilityLabel: props.accessibilityLabel,
		onLayout: (e: NeonEvent): void => {
			if (untrack<boolean>(resizing)) { return; }
			width = e.width;
			height = e.height;
		},
		children: (host: Host, parent: HostNode, before: HostNode | null): void => {
			if (primaryLayer !== null) { (primaryLayer as NeonNode)(host, parent, before); }
			if (secondaryLayer !== null) { (secondaryLayer as NeonNode)(host, parent, before); }
			moving(host, parent, before);
		},
	});
}
