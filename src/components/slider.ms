// @react-native-community/slider: a native UISlider / SeekBar, `<input type=range>` in the
// browser. Values cross the wire as decimal text; the host reports a drag as a value change
// (phase 4) and the release as sliding complete (phase 7).

import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { Accessor } from "../core/signal";
import { NeonNode, VAttr, VEvent, RefFn, hostElement, evt, dynAttr } from "../render/node";
import { AccessibilityProps, accessibilityAttrs, flagAttr, stringAttr } from "./primitives";

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

function numberAttr(attrs: VAttr[], name: string, value: Accessor<float64> | null, fallback: float64): void {
	if (value === null) {
		attrs.push(dynAttr(name, (): string | null => fallback.toString()));
		return;
	}
	const read = value as Accessor<float64>;
	attrs.push(dynAttr(name, (): string | null => read().toString()));
}

// RN's Slider snaps a reported value to `step` from the minimum, so every host reports the
// same numbers even when its native control is continuous.
export function snapSliderValue(raw: float64, minimum: float64, maximum: float64, step: float64): float64 {
	let v = Math.min(Math.max(raw, minimum), maximum);
	if (step > 0) {
		v = minimum + Math.round((v - minimum) / step) * step;
		v = Math.min(v, maximum);
	}
	return v;
}

export function Slider(props: SliderProps): NeonNode {
	const attrs: VAttr[] = [];
	numberAttr(attrs, "minimumValue", props.minimumValue, 0);
	numberAttr(attrs, "maximumValue", props.maximumValue, 1);
	numberAttr(attrs, "step", props.step, 0);
	numberAttr(attrs, "value", props.value, 0);
	flagAttr(attrs, "disabled", props.disabled);
	flagAttr(attrs, "inverted", props.inverted);
	stringAttr(attrs, "minimumTrackTintColor", props.minimumTrackTintColor);
	stringAttr(attrs, "maximumTrackTintColor", props.maximumTrackTintColor);
	stringAttr(attrs, "thumbTintColor", props.thumbTintColor);
	if (props.accessibilityRole === null) { attrs.push(dynAttr("accessibilityRole", (): string | null => "adjustable")); }
	accessibilityAttrs(props, attrs);
	const minimum = props.minimumValue;
	const maximum = props.maximumValue;
	const stepOf = props.step;
	const snap = (text: string): float64 => snapSliderValue(
		parseFloat(text),
		minimum === null ? 0 : (minimum as Accessor<float64>)(),
		maximum === null ? 1 : (maximum as Accessor<float64>)(),
		stepOf === null ? 0 : (stepOf as Accessor<float64>)(),
	);
	const evts: VEvent[] = [];
	const change = props.onValueChange;
	const start = props.onSlidingStart;
	let sliding = false;
	if (change !== null || start !== null) {
		evts.push(evt("onValueChange", (e: NeonEvent): void => {
			const v = snap(e.value);
			if (!sliding) {
				sliding = true;
				if (start !== null) { (start as (x: float64) => void)(v); }
			}
			if (change !== null) { (change as (x: float64) => void)(v); }
		}));
	}
	const complete = props.onSlidingComplete;
	evts.push(evt("onSlidingComplete", (e: NeonEvent): void => {
		sliding = false;
		if (complete !== null) { (complete as (x: float64) => void)(snap(e.value)); }
	}));
	if (props.onLayout !== null) { evts.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	let style: (() => Style) | null = null;
	if (props.style !== null) { style = props.style as () => Style; }
	return hostElement("slider", attrs, evts, null, style, props.ref);
}
