import { createStyles, styleOf } from "../../src/macros/ui/style";
import { Style } from "../../src/render/style";
import { createTheme, themeOf } from "../../src/macros/ui/theme";
import { FOOT_SLANT_RUN, FOOT_SLANT, GITHUB_MARK } from "./styleFoldConsts";

const EDGE = 24;
const RUN = 99;
const theme = createTheme({ mono: "monospace", line: "#222", sp2: 8 });

const geass = createStyles({
	bar: { paddingLeft: EDGE, width: FOOT_SLANT_RUN, clipPath: FOOT_SLANT, backgroundImage: GITHUB_MARK },
	pin: { top: -8, left: -63, marginRight: -6, zIndex: 2 },
	font: { fontFamily: "'Berkeley Mono', " + theme.mono, boxShadow: "inset 0 1px 0 " + theme.line },
	grad: { backgroundImage: "linear-gradient(#000, " + "#fff)" },
	math: { width: EDGE * 2 - 4, height: 7 / 2, flex: 1.5 / 2, minWidth: -EDGE, fontFamily: 1 + 2 + "px", maxHeight: -7 / 2 },
});

function rule(s: Style): string {
	return s.cssId === null ? "<no class>" : "." + (s.cssId as string) + "{";
}

function baked(s: Style): string {
	return s.css === null ? "<inline>" : s.css as string;
}

test "a module const, same module or imported, bakes into the class rule" {
	assert geass.bar.paddingLeft === 24 && geass.bar.width === 28, "both lanes read the folded values";
	assert geass.bar.clipPath === "polygon(0 0, 100% 0, calc(100% - 14px) 100%, 0 100%)", geass.bar.clipPath as string;
	when (js) {
		assert baked(geass.bar) === rule(geass.bar) + "width:28px;padding-left:24px;background-image:url(data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=);clip-path:polygon(0 0, 100% 0, calc(100% - 14px) 100%, 0 100%);}",
			baked(geass.bar);
	} else {
		assert geass.bar.cssId === null, "no css metadata off the browser lane";
	}
}

test "an imported const resolves its own module's names, not the caller's" {
	assert RUN === 99 && geass.bar.width === 28, "RUN inside the fixture is 14";
}

test "a negative literal bakes with its sign" {
	assert geass.pin.top === -8 && geass.pin.left === -63 && geass.pin.marginRight === -6, "native reads the signs";
	when (js) {
		assert baked(geass.pin) === rule(geass.pin) + "margin-right:-6px;top:-8px;left:-63px;z-index:2;}", baked(geass.pin);
	}
}

test "a theme token inside a concatenation spells its variable" {
	assert geass.font.fontFamily === "'Berkeley Mono', monospace" && geass.font.boxShadow === "inset 0 1px 0 #222", "the value reads through on both lanes";
	when (js) {
		assert baked(geass.font) === rule(geass.font) + "font-family:'Berkeley Mono', var(--mono);box-shadow:inset 0 1px 0 var(--line);}", baked(geass.font);
	}
}

test "a concatenation of literals bakes as one string" {
	when (js) {
		assert baked(geass.grad) === rule(geass.grad) + "background-image:linear-gradient(#000, #fff);}", baked(geass.grad);
	}
}

test "arithmetic folds to the value the program computes" {
	assert geass.math.width === 44 && geass.math.height === 3 && geass.math.flex === 0.75 && geass.math.minWidth === -24 && geass.math.maxHeight === -3, "integer constants divide as integers, toward zero";
	assert geass.math.fontFamily === "3px", "a number added before the string adds first";
	when (js) {
		assert baked(geass.math) === rule(geass.math) + "flex:0.75;width:44px;height:3px;min-width:-24px;max-height:-3px;font-family:3px;}", baked(geass.math);
	}
}

let gap = 4;
const loose = createStyles({
	numberTokenInMath: { padding: theme.sp2 * 2, color: "#fff" },
	numberTokenInText: { boxShadow: "0 0 " + theme.sp2 },
	letBound: { padding: gap, color: "#fff" },
	overZero: { width: 1.5 / 0 },
});

test "a value the macro cannot fold keeps the whole entry inline" {
	assert loose.numberTokenInMath.cssId === null && loose.numberTokenInMath.padding === 16, "a number token in arithmetic";
	assert loose.numberTokenInText.cssId === null && loose.numberTokenInText.boxShadow === "0 0 8", "a number token in a concatenation";
	assert loose.letBound.cssId === null && loose.letBound.padding === 4, "a let can be reassigned before the sheet reads it";
	assert loose.overZero.cssId === null, "a division by zero has no CSS spelling";
}
