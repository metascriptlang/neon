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
