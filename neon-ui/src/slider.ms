// @react-native-community/slider, drawn by Neon from Views: a track, its filled part and a
// thumb. A drag moves the value by its distance from where it started, as a UISlider does
// with its thumb; a tap on the track does not jump, because no host reports where in the
// slider a touch landed (event.ms `locationX` is Void-only).

import { NeonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { Accessor, accessor, createSignal, untrack } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode, RefFn, VAttr, VEvent, evt, hostElement } from "../../src/render/node";
import { defaultRole, layered } from "../../src/components/drawn";
import { AccessibilityProps, View, accessibilityAttrs } from "../../src/components/primitives";
import { PanResponder, PanResponderGestureState } from "../../src/components/panResponder";
import { MATERIAL_DISABLED, MATERIAL_PRIMARY, colorOr, flagOn, stateAttr, stateTokens } from "../../src/components/material";

interface SliderProps extends AccessibilityProps {
	value?: Accessor<float64> | null;
	minimumValue?: Accessor<float64> | null;
	maximumValue?: Accessor<float64> | null;
	step?: Accessor<float64> | null;
	disabled?: Accessor<boolean> | null;
	inverted?: Accessor<boolean> | null;
	minimumTrackTintColor?: Accessor<string> | null;
	maximumTrackTintColor?: Accessor<string> | null;
	thumbTintColor?: Accessor<string> | null;
	onValueChange?: ((value: float64) => void) | null;
	onSlidingStart?: ((value: float64) => void) | null;
	onSlidingComplete?: ((value: float64) => void) | null;
	style?: Accessor<Style> | null;
	ref?: RefFn | null;
	onLayout?: ((e: NeonEvent) => void) | null;
}

const THUMB = 24;
const TRACK = 4;
const MAXIMUM_TRACK = "#e0e0e0";
const ROOT: Style = { height: 40, justifyContent: "center" };

// RN's Slider snaps a reported value to `step` from the minimum.
export function snapSliderValue(raw: float64, minimum: float64, maximum: float64, step: float64): float64 {
	let v = Math.min(Math.max(raw, minimum), maximum);
	if (step > 0) {
		v = minimum + Math.round((v - minimum) / step) * step;
		v = Math.min(v, maximum);
	}
	return v;
}

function read(value: Accessor<float64> | null, fallback: float64): float64 {
	return value === null ? fallback : (value as Accessor<float64>)();
}

export function Slider(props: SliderProps): NeonNode {
	const { value, minimumValue, maximumValue, step, disabled, inverted, onValueChange, onSlidingStart, onSlidingComplete } = props;
	const minimum = (): float64 => read(minimumValue, 0);
	const maximum = (): float64 => read(maximumValue, 1);
	const [width, setWidth] = createSignal<number>(0);
	const [dragged, setDragged] = createSignal<float64>(0);
	const [dragging, setDragging] = createSignal(false);
	const shown = (): float64 => dragging() ? dragged() : snapSliderValue(read(value, 0), minimum(), maximum(), read(step, 0));
	const fraction = (): number => {
		const span = maximum() - minimum();
		const f = span > 0 ? (shown() - minimum()) / span : 0;
		return flagOn(inverted) ? 1 - f : f;
	};
	const travel = (): number => Math.max(0, width() - THUMB);
	const tint = (color: Accessor<string> | null, fallback: string): string => flagOn(disabled) ? MATERIAL_DISABLED : colorOr(color, fallback);
	const minimumTrack = props.minimumTrackTintColor;
	const maximumTrack = props.maximumTrackTintColor;
	const thumbTint = props.thumbTintColor;
	const rail = accessor((): Style => ({
		position: "absolute", left: THUMB / 2, right: THUMB / 2, height: TRACK, borderRadius: TRACK / 2,
		backgroundColor: tint(maximumTrack, MAXIMUM_TRACK),
	}));
	const fill = accessor((): Style => {
		const span = fraction() * travel();
		return {
			position: "absolute", height: TRACK, borderRadius: TRACK / 2, width: flagOn(inverted) ? travel() - span : span,
			left: flagOn(inverted) ? THUMB / 2 + span : THUMB / 2,
			backgroundColor: tint(minimumTrack, MATERIAL_PRIMARY),
		};
	});
	const thumb = accessor((): Style => ({
		position: "absolute", left: fraction() * travel(), width: THUMB, height: THUMB, borderRadius: THUMB / 2,
		backgroundColor: tint(thumbTint, MATERIAL_PRIMARY),
	}));
	let start: float64 = 0;
	let active = false;
	let last: float64 = 0;
	const report = (callback: ((v: float64) => void) | null, v: float64): void => {
		if (callback !== null) { (callback as (x: float64) => void)(v); }
	};
	const finish = (): void => {
		if (!active) { return; }
		active = false;
		setDragging(false);
		report(onSlidingComplete, last);
	};
	const pan = PanResponder.create({
		onStartShouldSetPanResponder: (e: NeonEvent, g: PanResponderGestureState): boolean => !flagOn(disabled),
		onPanResponderTerminationRequest: (e: NeonEvent, g: PanResponderGestureState): boolean => false,
		onPanResponderGrant: (e: NeonEvent, g: PanResponderGestureState): void => {
			start = untrack<float64>(shown);
			active = true;
			last = start;
			setDragged(start);
			setDragging(true);
			report(onSlidingStart, start);
		},
		onPanResponderMove: (e: NeonEvent, g: PanResponderGestureState): void => {
			const span = untrack<number>(travel);
			if (span <= 0) { return; }
			const direction = flagOn(inverted) ? -1 : 1;
			const raw = start + direction * g.dx / span * (maximum() - minimum());
			const v = snapSliderValue(raw, minimum(), maximum(), read(step, 0));
			if (v === last) { return; }
			last = v;
			setDragged(v);
			report(onValueChange, v);
		},
		onPanResponderRelease: (e: NeonEvent, g: PanResponderGestureState): void => { finish(); },
		onPanResponderTerminate: (e: NeonEvent, g: PanResponderGestureState): void => { finish(); },
	});
	const handlers = pan.panHandlers;
	const attrs: VAttr[] = [];
	defaultRole(attrs, props.accessibilityRole === null, "adjustable");
	accessibilityAttrs(props, attrs);
	stateAttr(attrs, (): string => stateTokens("", false, flagOn(disabled)));
	const layout = props.onLayout;
	const evts: VEvent[] = [evt("onLayout", (e: NeonEvent): void => {
		setWidth(e.width);
		if (layout !== null) { (layout as (e: NeonEvent) => void)(e); }
	})];
	const kids = element(<View {...handlers} style={{ position: "absolute", left: 0, top: 0, right: 0, bottom: 0, justifyContent: "center" }}>
		<View style={rail} />
		<View style={fill} />
		<View style={thumb} />
	</View>);
	return hostElement("view", attrs, evts, kids, layered(() => ROOT, props.style), props.ref);
}
