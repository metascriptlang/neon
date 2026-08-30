// Theme tokens (docs/STYLE.md §9, the S4c theme half).
//
// A token is named at compile time and valued at run time. `createTheme` bakes
// one `:root` rule holding every token's value and returns the object unchanged,
// so `theme.sp2` keeps its real type and reads as a plain field on native while
// the browser rule that uses it holds `var(--sp2)`.
//
// The split matters: a rule mentioning `var(--sp2)` is correct for every theme
// that will ever exist, so swapping a theme changes ONE variable and never
// rewrites, re-hashes, or re-registers a single style rule.
//
// A macro cannot resolve a value across modules (std/meta has node access, not
// symbol resolution), which is why the token's value is baked HERE, at the one
// site where it is written as a literal, rather than at each use.

import { Node, NodeKind, isFloatLiteral, intValue, floatValue, stringValue } from "std/meta";
import { registerCss } from "../../render/sheet";

// Transparent by design: a token keeps the arithmetic and the representation of
// its own type, and the name survives only so createStyles can tell `theme.sp2`
// from any other member read — the two are identical as syntax.
type Theme<T> = T;

// Registration happens at module init, not at first paint: a theme is a
// constant, and the `:root` key means a re-executed module replaces its own
// rule instead of growing the sheet.
export function themeOf<T>(o: T, css: string): Theme<T> {
	when (js) {
		if (css !== "") { registerCss(":root", css); }
	}
	return o;
}

function tokenValue(v: Node): string {
	if (v.kind === NodeKind.NumberLiteral) {
		if (isFloatLiteral(v)) { return floatValue(v).toString() + "px"; }
		return intValue(v).toString() + "px";
	}
	if (v.kind === NodeKind.StringLiteral) { return stringValue(v); }
	return "";
}

export macro createTheme(node: Node): Node {
	if (node.kind !== NodeKind.ObjectLiteral) {
		error("createTheme takes an object literal: createTheme({ sp2: 8, brand: \"#334\" })", node);
	}

	when (js) {
		const emitCss = true;
	} else {
		const emitCss = false;
	}

	let decls = "";
	for (let i = 0; i < node.properties.length; i += 1) {
		const v = node.properties[i];
		const name = node.keys[i];
		const text = tokenValue(v);
		if (text === "") {
			error("a theme token must be a number or string literal — its value is baked into one :root rule at compile time", v);
		}
		decls = decls + "--" + name + ":" + text + ";";
	}

	const css = emitCss && decls !== "" ? ":root{" + decls + "}" : "";

	return {
		kind: NodeKind.CallExpr, line: node.line, column: node.column,
		callee: { kind: NodeKind.Identifier, line: node.line, column: node.column, name: "themeOf" },
		arguments: [
			node,
			{ kind: NodeKind.StringLiteral, line: node.line, column: node.column, value: css },
		],
	};
}
