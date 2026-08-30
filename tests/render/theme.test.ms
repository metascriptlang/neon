// A theme token reads as its value everywhere and becomes a CSS variable on the
// browser lane (docs/STYLE.md §9, the S4c theme-token half).
//
// `theme.sp2` and `cfg.gap` are indistinguishable as syntax, so the macro tells
// them apart by TYPE: themeOf brands its result `Theme<T>`, an alias that is
// transparent at run time — the token keeps int32/string arithmetic and native
// reads it as a plain field — and survives expansion only as a name to match.
//
// The :root value carries NO unit, and the use site supplies one. That is what
// lets a single token serve a length property and a unitless one; baking `px`
// into the variable is how `opacity: theme.o5` used to render as `0.5px`.
//
// The rule text is asserted literally on purpose: a rule that names a variable
// is correct for every theme that will ever exist, so a theme swap must change
// one variable and never rewrite this string.

import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createTheme, themeOf } from "../../src/macros/ui/theme";
import { collectCss } from "../../src/render/sheet";

const theme = createTheme({ sp2: 8, o5: 0.5, brand: "#334" });

const s = createStyles({
	btn: { padding: theme.sp2, opacity: theme.o5, backgroundColor: theme.brand },
});

test "a token reads as its value on both lanes" {
	assert s.btn.padding === 8, "a numeric token is still readable as a number";
	assert s.btn.opacity === 0.5, "a fractional token keeps its fraction";
	assert s.btn.backgroundColor === "#334", "and a string token as a string";
}

test "the browser rule holds the variable, not the value" {
	when (js) {
		assert s.btn.cssId !== null, "a token entry still becomes one class";
		assert s.btn.css === "." + (s.btn.cssId as string) + "{padding:calc(var(--sp2) * 1px);opacity:var(--o5);background-color:var(--brand);}",
			"a length token gets its unit here, a unitless one and a string token do not";
	} else {
		assert s.btn.cssId === null, "no css metadata off the browser lane";
		assert s.btn.css === null, "and no rule text";
	}
}

test "the theme publishes its variables in one root rule" {
	when (js) {
		assert collectCss() === ":root{--sp2:8;--o5:0.5;--brand:#334;}", "one :root rule carries every token, unitless";
	}
}
