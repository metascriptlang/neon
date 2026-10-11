// react-native-paper's Chip, drawn by Neon with the Material look. The outlined mode's border
// is a coloured shell with a 1pt inset surface, since native hosts paint no borders. The
// body is one pressable (role button, or togglebutton once `selected` is given); `onClose`
// adds a sibling close pressable, so its press never reaches the body.

import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { Accessor, accessor } from "../core/signal";
import { element } from "../macros/ui/element";
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

export type ChipMode = "flat" | "outlined";

interface ChipProps extends AccessibilityProps {
	label?: Accessor<string> | null;
	children?: NeonNode | null;
	selected?: Accessor<boolean> | null;
	showSelectedCheck?: Accessor<boolean> | null;
	onPress?: ((e: NeonEvent) => void) | null;
	onClose?: (() => void) | null;
	closeIconAccessibilityLabel?: Accessor<string> | null;
	disabled?: Accessor<boolean> | null;
	icon?: Accessor<string> | null;
	mode?: Accessor<ChipMode> | null;
	selectedColor?: Accessor<string> | null;
	style?: Accessor<Style> | null;
}

const FLAT = "#e0e0e0";
const FLAT_SELECTED = "#bbdefb";
const FLAT_DISABLED = "#eeeeee";
const OUTLINED_SELECTED = "#e3f2fd";
const BODY: Style = {
	flexDirection: "row", alignItems: "center", paddingLeft: 12, paddingRight: 12,
};
const CLOSE: Style = {
	paddingLeft: 4, paddingRight: 10, alignItems: "center", justifyContent: "center",
};

export function Chip(props: ChipProps): NeonNode {
	const { label, selected, showSelectedCheck, onPress, onClose, disabled, icon, mode } = props;
	const isDisabled = (): boolean => flagOn(disabled);
	const isSelected = (): boolean => flagOn(selected);
	const outlined = (): boolean => {
		if (mode === null) { return false; }
		const m: ChipMode = (mode as Accessor<ChipMode>)();
		return m === "outlined";
	};
	const surfaceColor = (): string => {
		if (outlined()) { return isSelected() ? OUTLINED_SELECTED : MATERIAL_SURFACE; }
		if (isDisabled()) { return FLAT_DISABLED; }
		return isSelected() ? FLAT_SELECTED : FLAT;
	};
	const outlineColor = (): string => isSelected() ? MATERIAL_PRIMARY : MATERIAL_OUTLINE;
	const shell = (): Style => ({
		flexDirection: "row", alignSelf: "flex-start", borderRadius: 8,
		padding: outlined() ? 1 : 0,
		backgroundColor: outlined() ? outlineColor() : surfaceColor(),
	});
	const surface = accessor((): Style => ({
		flexDirection: "row", alignItems: "center", borderRadius: 7,
		height: outlined() ? 30 : 32, backgroundColor: surfaceColor(),
	}));
	const selectedColor = props.selectedColor;
	const ink = (): string => {
		return isDisabled() ? MATERIAL_DISABLED : colorOr(selectedColor, MATERIAL_ON_SURFACE);
	};
	const glyph = (): string => {
		if (icon !== null) { return (icon as Accessor<string>)(); }
		const check = showSelectedCheck === null || (showSelectedCheck as Accessor<boolean>)();
		return check && isSelected() ? "✓" : "";
	};
	const iconStyle = accessor((): Style => ({
		color: ink(), fontSize: 14, marginRight: glyph() === "" ? 0 : 6,
	}));
	const textStyle = accessor((): Style => ({ color: ink(), fontSize: 14 }));
	const content = label !== null
		? element(<Text style={textStyle}>{(label as Accessor<string>)()}</Text>)
		: element(<Text style={textStyle}>{props.children}</Text>);
	const attrs: VAttr[] = [];
	const role = selected === null ? "button" : "togglebutton";
	defaultRole(attrs, props.accessibilityRole === null, role);
	if (props.accessibilityLabel === null && label !== null) {
		const read = label as Accessor<string>;
		attrs.push(dynAttr("accessibilityLabel", (): string | null => read()));
	}
	accessibilityAttrs(props, attrs);
	stateAttr(attrs, (): string => stateTokens("", isSelected(), isDisabled()));
	const press = (e: NeonEvent): void => {
		if (isDisabled() || onPress === null) { return; }
		(onPress as (x: NeonEvent) => void)(e);
	};
	const bodyKids = element(<><Text style={iconStyle}>{glyph()}</Text>{content}</>);
	const bodyEvents = [evt("onPress", press)];
	const body = hostElement("pressable", attrs, bodyEvents, bodyKids, () => BODY, null);
	const shellStyle = layered(shell, props.style);
	if (onClose === null) {
		const alone = element(<View style={surface}>{body}</View>);
		return hostElement("view", [], [], alone, shellStyle, null);
	}
	const closeAttrs: VAttr[] = [];
	closeAttrs.push(dynAttr("accessibilityRole", (): string | null => "button"));
	const closeLabel = props.closeIconAccessibilityLabel;
	closeAttrs.push(dynAttr("accessibilityLabel", (): string | null => {
		return closeLabel === null ? "Close" : (closeLabel as Accessor<string>)();
	}));
	const close = (e: NeonEvent): void => {
		if (isDisabled()) { return; }
		(onClose as () => void)();
	};
	const closeKids = element(<Text style={textStyle}>×</Text>);
	const closeEvents = [evt("onPress", close)];
	const closer = hostElement("pressable", closeAttrs, closeEvents, closeKids, () => CLOSE, null);
	const kids = element(<View style={surface}>{body}{closer}</View>);
	return hostElement("view", [], [], kids, shellStyle, null);
}
