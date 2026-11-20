// Style — the portable style IR (docs/STYLE.md §3).
//
// Flat by design: one vocabulary covering layout + paint + text. Hosts project
// the subset they understand (docs/STYLE.md §5), so there is no ViewStyle /
// TextStyle split. This module must not import Yoga, void, or any host type.
//
// `null` means unset. Dimensions are `number | string`: a bare number is points,
// a string is "50%" or "auto".

import { styleInterfaceBody, setStyleFieldBody, mergeStyleBody, sameLayoutBody } from "../macros/style/fields";

export type FlexDirection = "row" | "column" | "row-reverse" | "column-reverse";
export type Justify = "flex-start" | "flex-end" | "center" | "space-between" | "space-around" | "space-evenly";
export type Align = "auto" | "flex-start" | "flex-end" | "center" | "stretch" | "baseline";
export type PositionType = "static" | "relative" | "absolute" | "fixed" | "sticky";
export type Wrap = "nowrap" | "wrap" | "wrap-reverse";
export type Display = "flex" | "none" | "contents" | "block" | "inline" | "inline-block" | "inline-flex";
export type Overflow = "visible" | "hidden" | "scroll" | "clip" | "auto";
export type Direction = "inherit" | "ltr" | "rtl";
export type WritingDirection = "auto" | "ltr" | "rtl";
export type TextAlign = "auto" | "left" | "center" | "right" | "justify";
export type FontWeight = "normal" | "bold"
	| "100" | "200" | "300" | "400" | "500" | "600" | "700" | "800" | "900";
export type FontStyle = "normal" | "italic";
export type FontSizeAdjust = "none" | "from-font"
	| "ex-height from-font" | "cap-height from-font" | "ic-width from-font";
export type TextDecorationLine = "none" | "underline" | "line-through" | "underline line-through"
	| "overline" | "underline overline" | "overline line-through" | "underline overline line-through";
export type TextDecorationStyle = "solid" | "double" | "dotted" | "dashed" | "wavy";
export type BorderStyle = "solid" | "dotted" | "dashed";
export type BoxSizing = "border-box" | "content-box";
export type Isolation = "auto" | "isolate";
export type BackfaceVisibility = "visible" | "hidden";
export type UserSelect = "auto" | "none" | "text" | "contain" | "all";
export type Cursor = "auto" | "default" | "pointer" | "text" | "crosshair" | "col-resize" | "row-resize";
export type TextTransform = "none" | "capitalize" | "uppercase" | "lowercase";
export type WhiteSpace = "normal" | "nowrap" | "pre" | "pre-wrap" | "pre-line" | "break-spaces";
export type ObjectFit = "cover" | "contain" | "fill" | "scale-down" | "none";
export type BorderCollapse = "collapse" | "separate";

styleInterfaceBody("block");

export interface StyleClaim {
	id: int32;
	field: string;
	read: (style: Style) => StyleValue;
	settle: (won: boolean) => void;
}

export interface ClaimMark {
	claim: StyleClaim;
	value: StyleValue;
	won: boolean;
}

styleInterfaceBody(0);

// Every style field's value fits this one union: string-literal unions are
// strings at runtime, dimensions are number | string, null means unset. It is
// the wire type of the per-property channel (setStyleProp / VDynStyle).
export type StyleValue = number | string | null;

export function isBoldWeight(weight: FontWeight | null): boolean {
	return weight === "bold" || weight === "600" || weight === "700"
		|| weight === "800" || weight === "900";
}

export function emptyStyle(): Style {
	return {};
}

// The per-property write behind reactive style fields (docs/STYLE.md §6). One
// switch instead of 40 setters on every host; the enum-ish fields narrow from
// the wire union with a cast because the checker cannot see which names carry
// which member.
setStyleFieldBody(0);

sameLayoutBody(0);

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

function noBreakpointTable(base: Style, over: Style): StyleBlock[] {
	throw new Error("a style carries media blocks but no breakpoint table was loaded: build the table with createBreakpoints from src/render/breakpoints");
}

let layerMedia: (base: Style, over: Style) => StyleBlock[] = noBreakpointTable;

export function installMediaLayering(layer: (base: Style, over: Style) => StyleBlock[]): void {
	layerMedia = layer;
}

export function mergeMedia(base: Style, over: Style): StyleBlock[] | null {
	return base.media === null ? over.media : layerMedia(base, over);
}

function marksClaim(marks: ClaimMark[], claim: StyleClaim): boolean {
	for (const mark of marks) {
		if (mark.claim.id === claim.id) { return true; }
	}
	return false;
}

export function mergeClaims(base: Style, over: Style): ClaimMark[] | null {
	const below = base.claims;
	const above = over.claims;
	if (below === null) { return above; }
	const out: ClaimMark[] = [];
	for (const mark of below as ClaimMark[]) {
		if (above !== null && marksClaim(above as ClaimMark[], mark.claim)) { continue; }
		const shadowed = mark.won && mark.claim.read(over) !== null;
		out.push(shadowed ? { claim: mark.claim, value: mark.value, won: false } : mark);
	}
	if (above !== null) {
		for (const mark of above as ClaimMark[]) { out.push(mark); }
	}
	return out;
}

function holds(style: Style, mark: ClaimMark): boolean {
	return mark.won && mark.claim.read(style) === mark.value;
}

export function claimed(style: Style, field: string): boolean {
	const marks = style.claims;
	if (marks === null) { return false; }
	for (const mark of marks as ClaimMark[]) {
		if (mark.claim.field === field && holds(style, mark)) { return true; }
	}
	return false;
}

export function settleClaims(style: Style): void {
	const marks = style.claims;
	if (marks === null) { return; }
	for (const mark of marks as ClaimMark[]) { mark.claim.settle(holds(style, mark)); }
}

export function claimedFields(style: Style): string[] {
	const marks = style.claims;
	const out: string[] = [];
	if (marks === null) { return out; }
	for (const mark of marks as ClaimMark[]) {
		if (holds(style, mark)) { out.push(mark.claim.field); }
	}
	return out;
}

export function unclaimedStyle(style: Style): Style {
	const fields = claimedFields(style);
	if (fields.length === 0) { return style; }
	const copy = mergeStyle(style, {});
	for (const field of fields) { setStyleField(copy, field, null); }
	return copy;
}
