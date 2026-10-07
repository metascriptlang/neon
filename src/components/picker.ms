// @react-native-picker/picker: a native menu (iOS UIMenu button, Android Spinner) and a
// `<select>` in the browser. Items arrive as an `items` array instead of `<Picker.Item>`
// children (WORKAROUND.md M2); the wire carries labels and the selected index.

import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { Accessor } from "../core/signal";
import { NeonNode, VAttr, VEvent, RefFn, hostElement, evt, dynAttr } from "../render/node";
import { AccessibilityProps, accessibilityAttrs, stringAttr } from "./primitives";

export interface PickerItem {
	label: string;
	value: string;
}

export type PickerMode = "dialog" | "dropdown";

interface PickerProps extends AccessibilityProps {
	items: Accessor<PickerItem[]>;
	selectedValue?: Accessor<string> | null;
	onValueChange?: ((value: string, index: int32) => void) | null;
	enabled?: Accessor<boolean> | null;
	mode?: Accessor<PickerMode> | null;
	prompt?: Accessor<string> | null;
	color?: Accessor<string> | null;
	style?: Accessor<Style> | null;
	ref?: RefFn | null;
	onLayout?: ((e: NeonEvent) => void) | null;
}

export const PICKER_FIELD = "\x1f";
export const PICKER_RECORD = "\x1e";

export function pickerItemsText(items: PickerItem[]): string {
	let out = "";
	for (let i = 0; i < items.length; i += 1) {
		if (i > 0) { out += PICKER_RECORD; }
		out += items[i].label + PICKER_FIELD + items[i].value;
	}
	return out;
}

export function pickerIndexOf(items: PickerItem[], value: string): int32 {
	for (let i = 0; i < items.length; i += 1) {
		if (items[i].value === value) { return i as int32; }
	}
	return -1;
}

export function Picker(props: PickerProps): NeonNode {
	const items = props.items;
	const selected = props.selectedValue;
	const attrs: VAttr[] = [];
	attrs.push(dynAttr("items", (): string | null => pickerItemsText(items())));
	attrs.push(dynAttr("selectedIndex", (): string | null => {
		const list = items();
		if (selected === null) { return list.length > 0 ? "0" : "-1"; }
		return pickerIndexOf(list, (selected as Accessor<string>)()).toString();
	}));
	const enabled = props.enabled;
	if (enabled !== null) {
		const read = enabled as Accessor<boolean>;
		attrs.push(dynAttr("disabled", (): string | null => read() ? "false" : "true"));
	}
	const mode = props.mode;
	if (mode !== null) {
		const read = mode as Accessor<PickerMode>;
		attrs.push(dynAttr("mode", (): string | null => { const m: PickerMode = read(); return m; }));
	}
	stringAttr(attrs, "prompt", props.prompt);
	stringAttr(attrs, "color", props.color);
	if (props.accessibilityRole === null) { attrs.push(dynAttr("accessibilityRole", (): string | null => "combobox")); }
	accessibilityAttrs(props, attrs);
	const evts: VEvent[] = [];
	const change = props.onValueChange;
	if (change !== null) {
		evts.push(evt("onValueChange", (e: NeonEvent): void => {
			const index = parseInt(e.value) as int32;
			const list = items();
			if (index < 0 || index >= list.length) { throw `Picker: the host reported item ${e.value} of ${list.length}`; }
			(change as (v: string, i: int32) => void)(list[index].value, index);
		}));
	}
	if (props.onLayout !== null) { evts.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	let style: (() => Style) | null = null;
	if (props.style !== null) { style = props.style as () => Style; }
	return hostElement("picker", attrs, evts, null, style, props.ref);
}
