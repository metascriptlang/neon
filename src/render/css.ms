// CSS text for a Style at run time — what the string renderer writes into a
// `style="…"` attribute (docs/STYLE.md §5).
//
// Third spelling of the same vocabulary, beside the rule text the macro bakes
// at expansion (macros/ui/style.ms cssDecl) and the CSSOM writes in
// platform/browser/dom.ms. Kept apart for the same reason those two are: each
// consumes a different form — a Node at expansion, a CSSOM object, a runtime
// Style. tests/render/ssrStyle.test.ms pins this one against the macro's rule
// text so the pair cannot drift apart silently.
//
// One emitter per unit rule rather than one emitter plus a name table: the
// call site already knows whether a field is a length, a bare ratio or a word,
// same split as len/num/word in the DOM host.

import { Style } from "./style";

function kebabCase(name: string): string {
	const lower = "abcdefghijklmnopqrstuvwxyz";
	let out = "";
	for (let i = 0; i < name.length; i += 1) {
		const c = name.charCodeAt(i);
		if (c >= 65 && c <= 90) {
			out = out + "-" + lower.charAt(c - 65);
		} else {
			out = out + name.charAt(i);
		}
	}
	return out;
}

// A bare number is points, which on the web is px; a string is already CSS.
function cssLen(name: string, v: number | string | null): string {
	if (v === null) { return ""; }
	if (typeof v === "string") { return kebabCase(name) + ":" + (v as string) + ";"; }
	return kebabCase(name) + ":" + `${v as number}` + "px;";
}

function cssPx(name: string, v: number | null): string {
	if (v === null) { return ""; }
	return kebabCase(name) + ":" + `${v as number}` + "px;";
}

// flex, the flex ratios, aspectRatio, opacity — unitless in CSS too.
function cssRatio(name: string, v: number | null): string {
	if (v === null) { return ""; }
	return kebabCase(name) + ":" + `${v as number}` + ";";
}

function cssWord(name: string, v: string | null): string {
	if (v === null) { return ""; }
	return kebabCase(name) + ":" + (v as string) + ";";
}

// Field by field in declaration order, because unset is `null` rather than
// absence and the flat IR has no key iteration.
export function styleToCss(s: Style): string {
	let out = "";
	out = out + cssWord("flexDirection", s.flexDirection as string | null);
	out = out + cssWord("justifyContent", s.justifyContent as string | null);
	out = out + cssWord("alignItems", s.alignItems as string | null);
	out = out + cssWord("alignSelf", s.alignSelf as string | null);
	out = out + cssWord("alignContent", s.alignContent as string | null);
	out = out + cssWord("position", s.position as string | null);
	out = out + cssWord("flexWrap", s.flexWrap as string | null);
	out = out + cssWord("display", s.display as string | null);

	out = out + cssRatio("flex", s.flex);
	out = out + cssRatio("flexGrow", s.flexGrow);
	out = out + cssRatio("flexShrink", s.flexShrink);
	out = out + cssLen("flexBasis", s.flexBasis);

	out = out + cssLen("width", s.width);
	out = out + cssLen("height", s.height);
	out = out + cssLen("minWidth", s.minWidth);
	out = out + cssLen("minHeight", s.minHeight);
	out = out + cssLen("maxWidth", s.maxWidth);
	out = out + cssLen("maxHeight", s.maxHeight);
	out = out + cssRatio("aspectRatio", s.aspectRatio);

	out = out + cssLen("margin", s.margin);
	out = out + cssLen("marginTop", s.marginTop);
	out = out + cssLen("marginBottom", s.marginBottom);
	out = out + cssLen("marginLeft", s.marginLeft);
	out = out + cssLen("marginRight", s.marginRight);

	out = out + cssLen("padding", s.padding);
	out = out + cssLen("paddingTop", s.paddingTop);
	out = out + cssLen("paddingBottom", s.paddingBottom);
	out = out + cssLen("paddingLeft", s.paddingLeft);
	out = out + cssLen("paddingRight", s.paddingRight);

	out = out + cssLen("top", s.top);
	out = out + cssLen("left", s.left);
	out = out + cssLen("right", s.right);
	out = out + cssLen("bottom", s.bottom);

	out = out + cssLen("gap", s.gap);
	out = out + cssLen("rowGap", s.rowGap);
	out = out + cssLen("columnGap", s.columnGap);

	out = out + cssWord("backgroundColor", s.backgroundColor);
	out = out + cssPx("borderWidth", s.borderWidth);
	out = out + cssWord("borderColor", s.borderColor);
	out = out + cssPx("borderRadius", s.borderRadius);
	out = out + cssRatio("opacity", s.opacity);

	out = out + cssWord("color", s.color);
	out = out + cssPx("fontSize", s.fontSize);
	out = out + cssWord("fontWeight", s.fontWeight as string | null);
	out = out + cssWord("textAlign", s.textAlign as string | null);
	return out;
}
