import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { Accessor } from "../core/signal";
import { NeonNode, VAttr, VEvent, RefFn, hostElement, evt } from "../render/node";
import { AccessibilityProps, accessibilityAttrs, flagAttr, stringAttr } from "./primitives";

interface SwitchProps extends AccessibilityProps {
	value?: Accessor<boolean> | null;
	onValueChange?: ((value: boolean) => void) | null;
	disabled?: Accessor<boolean> | null;
	thumbColor?: Accessor<string> | null;
	trackColorOn?: Accessor<string> | null;
	trackColorOff?: Accessor<string> | null;
	style?: Accessor<Style> | null;
	ref?: RefFn | null;
	onLayout?: ((e: NeonEvent) => void) | null;
}

export function Switch(props: SwitchProps): NeonNode {
	const attrs: VAttr[] = [];
	flagAttr(attrs, "value", props.value);
	flagAttr(attrs, "disabled", props.disabled);
	stringAttr(attrs, "thumbColor", props.thumbColor);
	stringAttr(attrs, "trackColorOn", props.trackColorOn);
	stringAttr(attrs, "trackColorOff", props.trackColorOff);
	accessibilityAttrs(props, attrs);
	const evts: VEvent[] = [];
	const change = props.onValueChange;
	if (change !== null) {
		evts.push(evt("onValueChange", (e: NeonEvent): void => { (change as (v: boolean) => void)(e.value === "true"); }));
	}
	if (props.onLayout !== null) { evts.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	let style: (() => Style) | null = null;
	if (props.style !== null) { style = props.style as () => Style; }
	return hostElement("switch", attrs, evts, null, style, props.ref);
}
