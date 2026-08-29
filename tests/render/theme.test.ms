// A theme token reads as its value everywhere and becomes a CSS variable on the
// browser lane (docs/STYLE.md §9, the S4c theme-token half).
//
// The arrow in `createStyles(theme => ({ ... }))` is a MARKER, not a runtime
// function: the macro strips it and emits the body, so `theme.sp2` binds to the
// module-level const and keeps its real type. That is what lets one entry carry
// the value on native and `var(--sp2)` in the baked rule on web.
//
// The rule text is asserted literally on purpose: a rule that names a variable
// is correct for every theme that will ever exist, so a theme swap must change
// one variable and never rewrite this string.

import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createTheme, themeOf } from "../../src/macros/ui/theme";
import { collectCss } from "../../src/render/sheet";

const theme = createTheme({ sp2: 8, brand: "#334" });

const s = createStyles(theme => ({
	btn: { padding: theme.sp2, backgroundColor: theme.brand },
}));

test "a token reads as its value on both lanes" {
	assert s.btn.padding === 8, "a numeric token is still readable as a number";
	assert s.btn.backgroundColor === "#334", "and a string token as a string";
}

test "the browser rule holds the variable, not the value" {
	when (js) {
		assert s.btn.cssId !== null, "a token entry still becomes one class";
		assert s.btn.css === "." + (s.btn.cssId as string) + "{padding:var(--sp2);background-color:var(--brand);}",
			"the rule references the variable so a theme swap never rewrites it";
	} else {
		assert s.btn.cssId === null, "no css metadata off the browser lane";
		assert s.btn.css === null, "and no rule text";
	}
}

test "the theme publishes its variables in one root rule" {
	when (js) {
		assert collectCss() === ":root{--sp2:8px;--brand:#334;}", "one :root rule carries every token";
	}
}
