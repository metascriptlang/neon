import { htmlTagFor } from "./node";

export const VIEW_CLASS = "neon-view";
export const TEXT_CLASS = "neon-text";

export const RN_WEB_BASE_CSS =
	":where(.neon-view){align-content:flex-start;align-items:stretch;" +
	"background-color:transparent;border:0 solid black;box-sizing:border-box;display:flex;" +
	"flex-basis:auto;flex-direction:column;flex-shrink:0;list-style:none;margin:0;" +
	"min-height:0;min-width:0;padding:0;position:relative;text-decoration:none;z-index:0}" +
	":where(button.neon-view){font:inherit;color:inherit;text-align:inherit}" +
	":where(.neon-text){background-color:transparent;border:0 solid black;" +
	"box-sizing:border-box;list-style:none;margin:0;padding:0;position:relative;" +
	"text-decoration:none;white-space:pre-wrap;overflow-wrap:break-word}";

export const SERVED_HEAD = "data-neon-head";

export const SCROLL_CLASS = "neon-scrollview";

export const SCROLL_CSS =
	`.${SCROLL_CLASS}{overflow-x:hidden;overflow-y:auto}.neon-hide-horizontal::-webkit-scrollbar:horizontal{height:0}.neon-hide-vertical::-webkit-scrollbar:vertical{width:0}@keyframes neon-refresh-spin{to{transform:rotate(360deg)}}.neon-refresh-indicator[aria-busy=true]{animation:neon-refresh-spin 1s linear infinite}`;

export const LINES_CLASS = "neon-lines";
export const TEXT_RULES_ID = "neon-text-props";

export const TEXT_CSS = ".neon-lines{display:-webkit-box !important;-webkit-box-orient:vertical;overflow:hidden}.neon-clip{text-overflow:clip}.neon-select-none{user-select:none;-webkit-user-select:none}.neon-select-text{user-select:text;-webkit-user-select:text}";

export struct WebRule {
	id: string;
	css: string;
}

export function clampedLines(value: string): boolean {
	return value !== "" && value !== "0";
}

export function linesClass(value: string): string {
	return `neon-lines-${value}`;
}

export function linesRule(value: string): WebRule {
	return { id: linesClass(value), css: `.${linesClass(value)}{-webkit-line-clamp:${value}}` };
}

export function webHtmlTag(tag: string): string {
	return match (tag) {
		"scrollview" => "div",
		_ => htmlTagFor(tag),
	};
}

export function webControlClass(tag: string): string {
	return match (tag) {
		"scrollview" => SCROLL_CLASS,
		_ => "",
	};
}

export function webRules(tag: string): WebRule[] {
	const rules: WebRule[] = [];
	if (webBaseClass(tag) !== "") { rules.push({ id: "neon-base", css: RN_WEB_BASE_CSS }); }
	match (tag) {
		"scrollview" => { rules.push({ id: SCROLL_CLASS, css: SCROLL_CSS }); },
		_ => {},
	}
	return rules;
}

export struct ScrollLook {
	overflowX: string;
	overflowY: string;
	touchAction: string;
	scrollbarWidth: string;
	overscrollBehaviorY: string;
	overflowAnchor: string;
	hideHorizontal: boolean;
	hideVertical: boolean;
}

export function scrollLook(
	horizontal: boolean,
	enabled: boolean,
	horizontalIndicator: boolean,
	verticalIndicator: boolean,
	refreshEnabled: boolean,
	keepsVisibleContent: boolean,
): ScrollLook {
	return {
		overflowX: enabled && horizontal ? "auto" : "hidden",
		overflowY: enabled && !horizontal ? "auto" : "hidden",
		touchAction: enabled ? (horizontal ? "pan-x" : "pan-y") : "none",
		scrollbarWidth: !horizontalIndicator && !verticalIndicator ? "none" : "auto",
		overscrollBehaviorY: refreshEnabled ? "contain" : "",
		overflowAnchor: keepsVisibleContent ? "none" : "",
		hideHorizontal: !horizontalIndicator,
		hideVertical: !verticalIndicator,
	};
}

export function scrollLookCss(look: ScrollLook): string {
	let css = "overflow-x:" + look.overflowX + ";overflow-y:" + look.overflowY +
		";touch-action:" + look.touchAction + ";scrollbar-width:" + look.scrollbarWidth + ";";
	if (look.overscrollBehaviorY !== "") { css = css + "overscroll-behavior-y:" + look.overscrollBehaviorY + ";"; }
	if (look.overflowAnchor !== "") { css = css + "overflow-anchor:" + look.overflowAnchor + ";"; }
	return css;
}

export function webBaseClass(tag: string): string {
	return match (tag) {
		"view" | "pressable" | "scrollview" | "svg" => VIEW_CLASS,
		"text" => TEXT_CLASS,
		_ => "",
	};
}

function ariaRole(role: string): string | null {
	return match (role) {
		"header" => "heading",
		"image" => "img",
		"adjustable" => "slider",
		"summary" => "region",
		"none" => "presentation",
		"text" => null,
		_ => role,
	};
}

function inputMode(keyboardType: string): string {
	return match (keyboardType) {
		"numeric" | "number-pad" => "numeric",
		"decimal-pad" => "decimal",
		"phone-pad" => "tel",
		"email-address" => "email",
		"url" => "url",
		_ => "text",
	};
}

export function domAttrValue(name: string, value: string): string | null {
	return match (name) {
		"accessibilityRole" => ariaRole(value),
		"editable" => value === "false" ? "" : null,
		"autoFocus" => value === "true" ? "" : null,
		"secureTextEntry" => value === "true" ? "password" : "text",
		"keyboardType" => inputMode(value),
		"autoCorrect" => value === "false" ? "off" : "on",
		"accessible" | "blurOnSubmit" | "multiline" | "placeholderTextColor" => null,
		_ => value,
	};
}

export function domAttrName(name: string): string {
	return match (name) {
		"accessibilityLabel" => "aria-label",
		"accessibilityHint" => "aria-description",
		"accessibilityRole" => "role",
		"editable" => "readonly",
		"keyboardType" => "inputmode",
		"returnKeyType" => "enterkeyhint",
		"autoCapitalize" => "autocapitalize",
		"autoCorrect" => "autocorrect",
		"maxLength" => "maxlength",
		"autoFocus" => "autofocus",
		"secureTextEntry" => "type",
		_ => name,
	};
}
