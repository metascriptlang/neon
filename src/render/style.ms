// Style — the portable style IR (docs/STYLE.md §3).
//
// Flat by design: one vocabulary covering layout + paint + text. Hosts project
// the subset they understand (docs/STYLE.md §5), so there is no ViewStyle /
// TextStyle split. This module must not import Yoga, void, or any host type.
//
// `null` means unset. Dimensions are `number | string`: a bare number is points,
// a string is "50%" or "auto".

import { styleInterfaceBody, setStyleFieldBody, mergeStyleBody } from "../macros/style/fields";

export type FlexDirection = "row" | "column" | "row-reverse" | "column-reverse";
export type Justify = "flex-start" | "flex-end" | "center" | "space-between" | "space-around" | "space-evenly";
export type Align = "auto" | "flex-start" | "flex-end" | "center" | "stretch" | "baseline";
export type PositionType = "static" | "relative" | "absolute";
export type Wrap = "nowrap" | "wrap" | "wrap-reverse";
export type Display = "flex" | "none";
export type Overflow = "visible" | "hidden" | "scroll";
export type TextAlign = "left" | "center" | "right";
export type FontWeight = "normal" | "bold";
export type FontStyle = "normal" | "italic";
export type TextDecorationLine = "none" | "underline" | "line-through" | "underline line-through";

styleInterfaceBody(0);

// Every style field's value fits this one union: string-literal unions are
// strings at runtime, dimensions are number | string, null means unset. It is
// the wire type of the per-property channel (setStyleProp / VDynStyle).
export type StyleValue = number | string | null;

export function emptyStyle(): Style {
	return {};
}

// The per-property write behind reactive style fields (docs/STYLE.md §6). One
// switch instead of 40 setters on every host; the enum-ish fields narrow from
// the wire union with a cast because the checker cannot see which names carry
// which member.
setStyleFieldBody(0);

// `style={[a, b, c]}` — later layers win at runtime when a layer is a sheet
// reference; all-literal arrays merge at expansion instead (element macro, S3).
export function layerStyles(layers: Style[]): Style {
	let acc = layers[0];
	for (let i = 1; i < layers.length; i += 1) {
		acc = mergeStyle(acc, layers[i]);
	}
	return acc;
}

// One layer of `style={[base, over]}`: a field set in `over` wins, an unset one
// falls through to `base`. Written field by field because unset is `null` rather
// than absence, so a copy cannot distinguish the two without naming each field.
mergeStyleBody(0);
