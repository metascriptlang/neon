// react-native-paper's RadioButton and RadioButton.Group, drawn by Neon with the Material look.
// The ring is a coloured disc with a surface disc inset 2pt, since native hosts paint no
// borders. A group row is one pressable (role radio) holding the mark and its label, so a
// screen reader reads the option once and a tap anywhere on the row selects it.

import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { Accessor, accessor } from "../core/signal";
import { element } from "../macros/ui/element";
import { For } from "../macros/ui/flow";
import { NeonNode, VAttr, dynAttr, evt, hostElement } from "../render/node";
import { defaultRole, layered } from "./drawn";
import { AccessibilityProps, Text, View, accessibilityAttrs } from "./primitives";
import {
	MATERIAL_DISABLED,
	MATERIAL_ON_SURFACE,
	MATERIAL_OUTLINE,
	MATERIAL_PRIMARY,
	MATERIAL_SURFACE,
	colorOr,
	flagOn,
	stateAttr,
	stateTokens,
} from "./material";

export type RadioStatus = "checked" | "unchecked";

export interface RadioOption {
	label: string;
	value: string;
}

const BUTTON_ROOT: Style = { padding: 6, alignItems: "center", justifyContent: "center" };
const GROUP_ROOT: Style = { flexDirection: "column" };
const ROW: Style = { flexDirection: "row", alignItems: "center", gap: 8, padding: 6 };

function radioMark(checked: () => boolean, tint: () => string): NeonNode {
	const ring = accessor((): Style => ({
		width: 20, height: 20, borderRadius: 10, padding: 2, backgroundColor: tint(),
	}));
	const surface = accessor((): Style => ({
		flex: 1, borderRadius: 8, alignItems: "center", justifyContent: "center",
		backgroundColor: MATERIAL_SURFACE,
	}));
	const dot = accessor((): Style => ({
		width: 10, height: 10, borderRadius: 5,
		backgroundColor: checked() ? tint() : MATERIAL_SURFACE,
	}));
	return element(<View style={ring}><View style={surface}><View style={dot} /></View></View>);
}

function markTint(
	checked: boolean,
	disabled: boolean,
	color: Accessor<string> | null,
	uncheckedColor: Accessor<string> | null,
): string {
	if (disabled) { return MATERIAL_DISABLED; }
	return checked ? colorOr(color, MATERIAL_PRIMARY) : colorOr(uncheckedColor, MATERIAL_OUTLINE);
}

function radioState(checked: boolean, disabled: boolean): string {
	return stateTokens(checked ? "checked" : "unchecked", false, disabled);
}

interface RadioButtonProps extends AccessibilityProps {
	value?: Accessor<string> | null;
	status?: Accessor<RadioStatus> | null;
	onPress?: ((e: NeonEvent) => void) | null;
	disabled?: Accessor<boolean> | null;
	color?: Accessor<string> | null;
	uncheckedColor?: Accessor<string> | null;
	style?: Accessor<Style> | null;
}

export function RadioButton(props: RadioButtonProps): NeonNode {
	const { status, onPress, disabled, color, uncheckedColor } = props;
	const isDisabled = (): boolean => flagOn(disabled);
	const isChecked = (): boolean => {
		if (status === null) { return false; }
		const s: RadioStatus = (status as Accessor<RadioStatus>)();
		return s === "checked";
	};
	const tint = (): string => markTint(isChecked(), isDisabled(), color, uncheckedColor);
	const attrs: VAttr[] = [];
	defaultRole(attrs, props.accessibilityRole === null, "radio");
	accessibilityAttrs(props, attrs);
	stateAttr(attrs, (): string => radioState(isChecked(), isDisabled()));
	const press = (e: NeonEvent): void => {
		if (isDisabled() || onPress === null) { return; }
		(onPress as (x: NeonEvent) => void)(e);
	};
	const style = layered(() => BUTTON_ROOT, props.style);
	const mark = radioMark(isChecked, tint);
	return hostElement("pressable", attrs, [evt("onPress", press)], mark, style, null);
}

interface RadioGroupProps extends AccessibilityProps {
	value?: Accessor<string> | null;
	onValueChange?: ((value: string) => void) | null;
	options: Accessor<RadioOption[]>;
	disabled?: Accessor<boolean> | null;
	color?: Accessor<string> | null;
	uncheckedColor?: Accessor<string> | null;
	labelColor?: Accessor<string> | null;
	style?: Accessor<Style> | null;
}

export function RadioGroup(props: RadioGroupProps): NeonNode {
	const { value, onValueChange, options, disabled, color, uncheckedColor, labelColor } = props;
	const isDisabled = (): boolean => flagOn(disabled);
	const labelStyle = accessor((): Style => ({
		fontSize: 16,
		color: isDisabled() ? MATERIAL_DISABLED : colorOr(labelColor, MATERIAL_ON_SURFACE),
	}));
	const row = (option: RadioOption): NeonNode => {
		const isChecked = (): boolean => {
			return value !== null && (value as Accessor<string>)() === option.value;
		};
		const tint = (): string => markTint(isChecked(), isDisabled(), color, uncheckedColor);
		const attrs: VAttr[] = [];
		attrs.push(dynAttr("accessibilityRole", (): string | null => "radio"));
		attrs.push(dynAttr("accessibilityLabel", (): string | null => option.label));
		stateAttr(attrs, (): string => radioState(isChecked(), isDisabled()));
		const press = (e: NeonEvent): void => {
			if (isDisabled() || onValueChange === null) { return; }
			(onValueChange as (v: string) => void)(option.value);
		};
		const mark = radioMark(isChecked, tint);
		const kids = element(<>{mark}<Text style={labelStyle}>{option.label}</Text></>);
		return hostElement("pressable", attrs, [evt("onPress", press)], kids, () => ROW, null);
	};
	const attrs: VAttr[] = [];
	defaultRole(attrs, props.accessibilityRole === null, "radiogroup");
	accessibilityAttrs(props, attrs);
	if (disabled !== null) { stateAttr(attrs, (): string => isDisabled() ? "disabled" : ""); }
	const rows = element(<For each={options()}>
		{(option: RadioOption, i: Accessor<number>): NeonNode => row(option)}
	</For>);
	return hostElement("view", attrs, [], rows, layered(() => GROUP_ROOT, props.style), null);
}
