// @react-native-community/checkbox, drawn by Neon with the Material look. The native hosts
// paint no borders, so the outline is a coloured box with a 2pt inset surface inside it.
// `indeterminate` is Flutter's tristate `null`: shown as a dash, and a press checks it.

import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { Accessor, accessor } from "../core/signal";
import { element } from "../macros/ui/element";
import { NeonNode, VAttr, evt, hostElement } from "../render/node";
import { defaultRole, layered } from "./drawn";
import { AccessibilityProps, Text, View, accessibilityAttrs } from "./primitives";
import {
	MATERIAL_DISABLED,
	MATERIAL_ON_PRIMARY,
	MATERIAL_OUTLINE,
	MATERIAL_PRIMARY,
	MATERIAL_SURFACE,
	colorOr,
	flagOn,
	stateAttr,
	stateTokens,
} from "./material";

interface CheckboxProps extends AccessibilityProps {
	value?: Accessor<boolean> | null;
	onValueChange?: ((value: boolean) => void) | null;
	disabled?: Accessor<boolean> | null;
	indeterminate?: Accessor<boolean> | null;
	color?: Accessor<string> | null;
	uncheckedColor?: Accessor<string> | null;
	style?: Accessor<Style> | null;
}

const ROOT: Style = { padding: 7, alignItems: "center", justifyContent: "center" };

export function Checkbox(props: CheckboxProps): NeonNode {
	const { value, onValueChange, disabled, indeterminate, color, uncheckedColor } = props;
	const isDisabled = (): boolean => flagOn(disabled);
	const isMixed = (): boolean => flagOn(indeterminate);
	const isChecked = (): boolean => !isMixed() && flagOn(value);
	const filled = (): boolean => isMixed() || isChecked();
	const tint = (): string => {
		if (isDisabled()) { return MATERIAL_DISABLED; }
		if (filled()) { return colorOr(color, MATERIAL_PRIMARY); }
		return colorOr(uncheckedColor, MATERIAL_OUTLINE);
	};
	const box = accessor((): Style => ({
		width: 18, height: 18, padding: 2, borderRadius: 2, backgroundColor: tint(),
	}));
	const surface = accessor((): Style => ({
		flex: 1, alignItems: "center", justifyContent: "center",
		backgroundColor: filled() ? tint() : MATERIAL_SURFACE,
	}));
	const markStyle = accessor((): Style => ({
		color: MATERIAL_ON_PRIMARY, fontSize: 12, fontWeight: "bold",
	}));
	const glyph = (): string => isMixed() ? "−" : isChecked() ? "✓" : "";
	const attrs: VAttr[] = [];
	defaultRole(attrs, props.accessibilityRole === null, "checkbox");
	accessibilityAttrs(props, attrs);
	stateAttr(attrs, (): string => {
		const checked = isMixed() ? "mixed" : isChecked() ? "checked" : "unchecked";
		return stateTokens(checked, false, isDisabled());
	});
	const press = (e: NeonEvent): void => {
		if (isDisabled() || onValueChange === null) { return; }
		(onValueChange as (v: boolean) => void)(isMixed() ? true : !isChecked());
	};
	const kids = element(<View style={box}>
		<View style={surface}><Text style={markStyle}>{glyph()}</Text></View>
	</View>);
	const style = layered(() => ROOT, props.style);
	return hostElement("pressable", attrs, [evt("onPress", press)], kids, style, null);
}
