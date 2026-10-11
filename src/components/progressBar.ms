// Flutter's LinearProgressIndicator, react-native-paper's ProgressBar. Native hosts take
// points, not percentages, so the bar is a row of three flex children: a leading gap, the
// fill and a trailing gap whose flex values add up to one. Indeterminate mode moves a 30%
// segment across the track by stepping a signal from a 50ms interval, which runs only while
// the bar is indeterminate and is cleared when it stops or unmounts.

import { Style } from "../render/style";
import { Accessor, accessor, createSignal } from "../core/signal";
import { createEffect } from "../core/effect";
import { onCleanup } from "../core/cleanup";
import { element } from "../macros/ui/element";
import { NeonNode, VAttr, dynAttr, hostElement } from "../render/node";
import { defaultRole, layered } from "./drawn";
import { AccessibilityProps, View, accessibilityAttrs } from "./primitives";
import { MATERIAL_PRIMARY, colorOr, flagOn, stateAttr } from "./material";

interface ProgressBarProps extends AccessibilityProps {
	progress?: Accessor<float64> | null;
	indeterminate?: Accessor<boolean> | null;
	color?: Accessor<string> | null;
	trackColor?: Accessor<string> | null;
	visible?: Accessor<boolean> | null;
	style?: Accessor<Style> | null;
}

const TRACK_COLOR = "#bbdefb";
const STEP_MS = 50;
const STEPS_PER_TRACK = 20;
const SEGMENT = 0.3;

export struct BarSpan {
	lead: float64;
	fill: float64;
	tail: float64;
}

export function determinateSpan(progress: float64): BarSpan {
	const p = Math.min(Math.max(progress, 0.0), 1.0);
	return { lead: 0.0, fill: p, tail: 1.0 - p };
}

// Step `phase` of a sweep: the segment's head enters at the left edge, crosses the track,
// and its tail leaves at the right edge after `(1 + SEGMENT) * STEPS_PER_TRACK` steps.
export function sweepSpan(phase: int32): BarSpan {
	const t = (phase as float64) / (STEPS_PER_TRACK as float64);
	const head = Math.min(t, 1.0);
	const start = Math.min(Math.max(t - SEGMENT, 0.0), head);
	return { lead: start, fill: head - start, tail: 1.0 - head };
}

export function sweepSteps(): int32 {
	return Math.round((1.0 + SEGMENT) * (STEPS_PER_TRACK as float64)) as int32;
}

export function progressLabel(progress: float64): string {
	const p = Math.min(Math.max(progress, 0.0), 1.0);
	return (Math.round(p * 100.0) as int32).toString() + "%";
}

export function ProgressBar(props: ProgressBarProps): NeonNode {
	const { progress, indeterminate, color, trackColor, visible } = props;
	const isIndeterminate = (): boolean => flagOn(indeterminate);
	const amount = (): float64 => progress === null ? 0.0 : (progress as Accessor<float64>)();
	const [phase, setPhase] = createSignal(0);
	createEffect((): void => {
		if (!isIndeterminate()) { return; }
		const steps = sweepSteps();
		const id = setInterval((): void => { setPhase((phase() + 1) % steps); }, STEP_MS);
		onCleanup((): void => { clearInterval(id); });
	});
	const span = (): BarSpan => isIndeterminate() ? sweepSpan(phase()) : determinateSpan(amount());
	const shown = (): boolean => visible === null || (visible as Accessor<boolean>)();
	const track = (): Style => {
		const s: Style = {
			flexDirection: "row", height: 4, borderRadius: 2, overflow: "hidden",
			backgroundColor: colorOr(trackColor, TRACK_COLOR),
		};
		if (!shown()) { return { ...s, display: "none" }; }
		return s;
	};
	const lead = accessor((): Style => ({ flex: span().lead }));
	const fill = accessor((): Style => ({
		flex: span().fill, backgroundColor: colorOr(color, MATERIAL_PRIMARY),
	}));
	const tail = accessor((): Style => ({ flex: span().tail }));
	const attrs: VAttr[] = [];
	defaultRole(attrs, props.accessibilityRole === null, "progressbar");
	if (props.accessibilityLabel === null) {
		attrs.push(dynAttr("accessibilityLabel", (): string | null => {
			return isIndeterminate() ? "" : progressLabel(amount());
		}));
	}
	accessibilityAttrs(props, attrs);
	stateAttr(attrs, (): string => isIndeterminate() ? "busy" : "");
	const kids = element(<><View style={lead} /><View style={fill} /><View style={tail} /></>);
	return hostElement("view", attrs, [], kids, layered(track, props.style), null);
}
