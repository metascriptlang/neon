// Shared look and accessibility plumbing of the Neon-drawn Material controls.
// `accessibilityState` is a wire attribute: comma-separated tokens from RN's
// accessibilityState (checked, unchecked, mixed, selected, disabled, expanded, collapsed,
// busy), mapped by each host (ARIA, UIAccessibility traits and value, Android state).

import { Accessor } from "../core/signal";
import { VAttr, dynAttr } from "../render/node";

export const MATERIAL_PRIMARY = "#2196f3";
export const MATERIAL_ON_PRIMARY = "#ffffff";
export const MATERIAL_SURFACE = "#ffffff";
export const MATERIAL_ON_SURFACE = "#1c1b1f";
export const MATERIAL_OUTLINE = "#79747e";
export const MATERIAL_DISABLED = "#bdbdbd";
export const MATERIAL_SCRIM = "rgba(0,0,0,0.5)";

export function colorOr(color: Accessor<string> | null, fallback: string): string {
	return color === null ? fallback : (color as Accessor<string>)();
}

export function flagOn(flag: Accessor<boolean> | null): boolean {
	return flag !== null && (flag as Accessor<boolean>)();
}

export function stateAttr(attrs: VAttr[], tokens: () => string): void {
	attrs.push(dynAttr("accessibilityState", (): string | null => tokens()));
}

export function stateTokens(checked: string, selected: boolean, disabled: boolean): string {
	let out = checked;
	if (selected) { out += out === "" ? "selected" : ",selected"; }
	if (disabled) { out += out === "" ? "disabled" : ",disabled"; }
	return out;
}
