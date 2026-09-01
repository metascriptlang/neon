// Swapping a theme at run time (docs/STYLE.md §9, the deferred half of S4c).
//
// The point of spelling a token `var(--name)` is that a rule is correct for
// every theme that will ever exist. So a swap must change the `:root` rule and
// leave every entry rule BYTE-IDENTICAL — no rewrite, no re-hash, no new class
// on any mounted node. These tests assert the rule text before and after.
//
// `setTheme` takes an object literal for the same reason `createTheme` does: a
// macro reads literals, not symbols, so the token values must be visible at the
// call. Handing it a variable is a located error, never a silent no-op.
//
// Off the browser lane a swap is a no-op today: a native token was baked into
// the entry as a value, so changing it needs the signal path (a separate arc).
// That no-op is pinned here so it stays a known shape rather than a surprise.

import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createTheme, setTheme, themeOf, setThemeCss } from "../../src/macros/ui/theme";
import { collectCss, registerCss, onCssChange } from "../../src/render/sheet";

const theme = createTheme({ sp2: 8, brand: "#334" });

const s = createStyles({
	btn: { padding: theme.sp2, backgroundColor: theme.brand },
});

test "a swap rewrites the root rule and nothing else" {
	when (js) {
		// Spelled out rather than captured into a variable: on this lane a
		// `string | null` is boxed, so comparing the field to ITSELF is false
		// (the open union-equality row in BUGS.md). A literal pins more anyway.
		const rule = "." + (s.btn.cssId as string) + "{padding:calc(var(--sp2) * 1px);background-color:var(--brand);}";
		assert collectCss() === ":root{--sp2:8;--brand:#334;}", "the default theme is installed at module init";
		assert s.btn.css === rule, "the entry rule names variables, not values";
		setTheme({ sp2: 8, brand: "#111" });
		assert collectCss() === ":root{--sp2:8;--brand:#111;}", "the swap replaces the one root rule";
		assert s.btn.css === rule, "and the entry rule is untouched, byte for byte";
	} else {
		setTheme({ sp2: 8, brand: "#111" });
		assert s.btn.css === null, "off the browser lane a swap is a no-op";
	}
}

test "the sheet tells the host when it changed" {
	when (js) {
		let fired = 0;
		onCssChange(() => { fired += 1; });
		registerCss("n_probe", ".n_probe{color:red;}");
		assert fired === 1, "a new rule notifies the host so it can flush";
		setTheme({ sp2: 4, brand: "#334" });
		assert fired === 2, "and so does a theme swap";
		onCssChange(null);
	}
}
