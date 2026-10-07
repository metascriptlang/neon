// @react-native-community/datetimepicker as an inline field: UIDatePicker (compact) on iOS,
// a field that opens DatePickerDialog / TimePickerDialog on Android, `<input type=date|time|
// datetime-local>` in the browser. MetaScript has no `Date` instance yet, so values are local
// ISO-8601 text: "2026-10-07", "18:30", "2026-10-07T18:30" (WORKAROUND.md M3).

import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { Accessor } from "../core/signal";
import { NeonNode, VAttr, VEvent, RefFn, hostElement, evt, dynAttr } from "../render/node";
import { AccessibilityProps, accessibilityAttrs, flagAttr, stringAttr } from "./primitives";

export type DateTimeMode = "date" | "time" | "datetime";
export type DateTimeDisplay = "default" | "compact" | "inline" | "spinner";

interface DateTimePickerProps extends AccessibilityProps {
	value: Accessor<string>;
	mode?: Accessor<DateTimeMode> | null;
	display?: Accessor<DateTimeDisplay> | null;
	minimumDate?: Accessor<string> | null;
	maximumDate?: Accessor<string> | null;
	disabled?: Accessor<boolean> | null;
	accentColor?: Accessor<string> | null;
	textColor?: Accessor<string> | null;
	onChange?: ((value: string) => void) | null;
	style?: Accessor<Style> | null;
	ref?: RefFn | null;
	onLayout?: ((e: NeonEvent) => void) | null;
}

function pad2(n: int32): string {
	return n < 10 ? "0" + n.toString() : n.toString();
}

export function isoDate(year: int32, month: int32, day: int32): string {
	return year.toString() + "-" + pad2(month) + "-" + pad2(day);
}

export function isoTime(hour: int32, minute: int32): string {
	return pad2(hour) + ":" + pad2(minute);
}

export function DateTimePicker(props: DateTimePickerProps): NeonNode {
	const attrs: VAttr[] = [];
	const mode = props.mode;
	attrs.push(dynAttr("mode", (): string | null => {
		if (mode === null) { return "date"; }
		const m: DateTimeMode = (mode as Accessor<DateTimeMode>)();
		return m;
	}));
	const display = props.display;
	if (display !== null) {
		const read = display as Accessor<DateTimeDisplay>;
		attrs.push(dynAttr("display", (): string | null => { const d: DateTimeDisplay = read(); return d; }));
	}
	stringAttr(attrs, "minimumDate", props.minimumDate);
	stringAttr(attrs, "maximumDate", props.maximumDate);
	stringAttr(attrs, "value", props.value);
	flagAttr(attrs, "disabled", props.disabled);
	stringAttr(attrs, "accentColor", props.accentColor);
	stringAttr(attrs, "textColor", props.textColor);
	accessibilityAttrs(props, attrs);
	const evts: VEvent[] = [];
	const change = props.onChange;
	if (change !== null) {
		evts.push(evt("onValueChange", (e: NeonEvent): void => {
			if (e.value === "") { return; }
			(change as (v: string) => void)(e.value);
		}));
	}
	if (props.onLayout !== null) { evts.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	let style: (() => Style) | null = null;
	if (props.style !== null) { style = props.style as () => Style; }
	return hostElement("datetimepicker", attrs, evts, null, style, props.ref);
}
