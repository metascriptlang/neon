// @react-native-segmented-control/segmented-control, drawn by Neon with the Material look:
// a rounded track holding one pressable segment per value. The package reports a press as
// `onChange(event)` carrying `selectedSegmentIndex` and as `onValueChange(value)`; Neon hands
// `onChange` the index itself. Pressing the selected segment reports nothing, like UIKit.

import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { Accessor, accessor } from "../core/signal";
import { element } from "../macros/ui/element";
import { For } from "../macros/ui/flow";
import { NeonNode, VAttr, dynAttr, evt, hostElement } from "../render/node";
import { defaultRole, layered } from "./drawn";
import { AccessibilityProps, Text, accessibilityAttrs } from "./primitives";
import {
	MATERIAL_DISABLED,
	MATERIAL_ON_PRIMARY,
	MATERIAL_ON_SURFACE,
	MATERIAL_PRIMARY,
	colorOr,
	stateAttr,
	stateTokens,
} from "./material";

interface SegmentedControlProps extends AccessibilityProps {
	values: Accessor<string[]>;
	selectedIndex?: Accessor<int32> | null;
	onChange?: ((index: int32) => void) | null;
	onValueChange?: ((value: string) => void) | null;
	enabled?: Accessor<boolean> | null;
	tintColor?: Accessor<string> | null;
	backgroundColor?: Accessor<string> | null;
	style?: Accessor<Style> | null;
}

const TRACK_COLOR = "#e0e0e0";
const SEGMENT_TEXT: Style = { fontSize: 14, fontWeight: "normal" };
const SELECTED_TEXT: Style = { fontSize: 14, fontWeight: "bold" };

export function SegmentedControl(props: SegmentedControlProps): NeonNode {
	const { values, selectedIndex, onChange, onValueChange, enabled, tintColor } = props;
	const isEnabled = (): boolean => enabled === null || (enabled as Accessor<boolean>)();
	const current = (): int32 => selectedIndex === null ? -1 : (selectedIndex as Accessor<int32>)();
	const trackColor = props.backgroundColor;
	const track = (): Style => ({
		flexDirection: "row", padding: 2, borderRadius: 8,
		backgroundColor: colorOr(trackColor, TRACK_COLOR),
	});
	const segment = (value: string, index: Accessor<number>): NeonNode => {
		const isSelected = (): boolean => current() === (index() as int32);
		const box = accessor((): Style => ({
			flex: 1, alignItems: "center", justifyContent: "center", borderRadius: 6,
			paddingTop: 6, paddingBottom: 6, paddingLeft: 8, paddingRight: 8,
			backgroundColor: isSelected()
				? colorOr(tintColor, MATERIAL_PRIMARY)
				: colorOr(trackColor, TRACK_COLOR),
		}));
		const label = accessor((): Style => {
			let ink = isSelected() ? MATERIAL_ON_PRIMARY : MATERIAL_ON_SURFACE;
			if (!isEnabled()) { ink = MATERIAL_DISABLED; }
			const base = isSelected() ? SELECTED_TEXT : SEGMENT_TEXT;
			return { ...base, color: ink };
		});
		const attrs: VAttr[] = [];
		attrs.push(dynAttr("accessibilityRole", (): string | null => "tab"));
		attrs.push(dynAttr("accessibilityLabel", (): string | null => value));
		stateAttr(attrs, (): string => stateTokens("", isSelected(), !isEnabled()));
		const press = (e: NeonEvent): void => {
			if (!isEnabled() || isSelected()) { return; }
			const at = index() as int32;
			if (onChange !== null) { (onChange as (i: int32) => void)(at); }
			if (onValueChange !== null) { (onValueChange as (v: string) => void)(value); }
		};
		const kids = element(<Text style={label}>{value}</Text>);
		const events = [evt("onPress", press)];
		return hostElement("pressable", attrs, events, kids, box as () => Style, null);
	};
	const attrs: VAttr[] = [];
	defaultRole(attrs, props.accessibilityRole === null, "tablist");
	accessibilityAttrs(props, attrs);
	const segments = element(<For each={values()}>
		{(value: string, index: Accessor<number>): NeonNode => segment(value, index)}
	</For>);
	return hostElement("view", attrs, [], segments, layered(track, props.style), null);
}
