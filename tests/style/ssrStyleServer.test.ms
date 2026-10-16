// A snapshot render carries style the same way a mounted tree does
// (docs/STYLE.md §5): a static sheet entry becomes a class plus one rule in the
// registry, every other channel is written inline. Server markup that resolved
// styles differently from a live mount would hand the browser a tree it has to
// correct on hydration.

import { NeonNode } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { styleToCss } from "../../src/render/css";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { resetCss, cssRuleCount, mountSheet } from "../../src/render/sheet";
import { createSignal } from "../../src/core/signal";
import { View, Text } from "../../src/components/primitives";

const sheet = createStyles({
	btn: { padding: 8, backgroundColor: "#334" },
});

let wide = 700;
const MONO = "monospace";
const geass = createStyles({
	layered: { zIndex: 2, opacity: 0.5, width: 10 },
	computed: { width: wide, top: -8, zIndex: 2, fontFamily: "x, " + MONO },
});

test "a static sheet entry serializes as a class and registers its rule" {
	resetCss();
	const html = renderToString(<div style={sheet.btn}>hi</div>);
	const id = sheet.btn.cssId as string;
	assert html === "<div class=\"" + id + "\">hi</div>", "class, no inline copy of the rule";
	assert cssRuleCount() === 1, "rendering the node mounted the rule";
	assert mountSheet() === "<style>." + id + "{padding:8px;background-color:#334;}</style>", "the page emits the whole registry in one block";
}

test "the runtime spelling equals the rule the macro baked" {
	assert (sheet.btn.css as string) === "." + (sheet.btn.cssId as string) + "{" + styleToCss(sheet.btn) + "}", "one vocabulary, two spellings, same text";
}

test "a baked rule spells every unitless field as the runtime does" {
	const css = geass.layered.css as string;
	assert css.indexOf("z-index:2;") >= 0 && css.indexOf("opacity:0.5;") >= 0 && css.indexOf("width:10px;") >= 0, css;
}

test "an entry with a value the macro cannot spell keeps every field inline" {
	assert geass.computed.cssId === null, "no class rule that would drop the computed fields";
	const html = renderToString(<View style={geass.computed}></View>);
	assert html === "<div class=\"neon-view\" style=\"" + styleToCss(geass.computed) + "\"></div>", html;
	assert styleToCss(geass.computed).indexOf("width:700px;") >= 0 && styleToCss(geass.computed).indexOf("top:-8px;") >= 0 && styleToCss(geass.computed).indexOf("font-family:x, monospace;") >= 0, styleToCss(geass.computed);
}

test "an inline style literal serializes into the style attribute" {
	const s = styleOf({ width: "50%", opacity: 0.5, color: "#fff" });
	assert renderToString(<p style={s}></p>) === "<p style=\"width:50%;opacity:0.5;color:#fff;\"></p>", "a string dimension passes through, a ratio takes no unit";
}

test "an empty value writes no declaration, as an empty CSSOM write sets none" {
	const s = styleOf({ color: "", width: "", opacity: 0.5 });
	assert renderToString(<p style={s}></p>) === "<p style=\"opacity:0.5;\"></p>", renderToString(<p style={s}></p>);
	const none = styleOf({ color: "" });
	assert renderToString(<p style={none}></p>) === "<p></p>", renderToString(<p style={none}></p>);
}

test "quoted inline CSS stays inside its HTML attribute" {
	const font = styleOf({ fontFamily: "\"A&B\"" });
	assert renderToString(<p style={font}></p>) ===
		"<p style=\"font-family:&quot;A&amp;B&quot;;\"></p>";
}

test "a reactive whole-style thunk serializes its value at render time" {
	const [w, setW] = createSignal(10);
	const n: NeonNode = <div style={styleOf({ width: w() })}></div>;
	assert renderToString(n) === "<div style=\"width:10px;\"></div>", "the thunk runs";
	setW(20);
	assert renderToString(n) === "<div style=\"width:20px;\"></div>", "a second render re-reads it";
}

test "per-property thunks land over the static base" {
	const seven = (): number => 7;
	const n: NeonNode = <div style={{ width: seven(), padding: 4 }}></div>;
	assert renderToString(n) === "<div style=\"width:7px;padding:4px;\"></div>", "declaration order, base and override together";
}

test "a class from a sheet joins the class attribute already on the node" {
	const n: NeonNode = <div class="x" style={sheet.btn}></div>;
	assert renderToString(n) === "<div class=\"x " + (sheet.btn.cssId as string) + "\"></div>", "one class attribute, not two";
	const marked: NeonNode = <div class={"x&\"y"} style={sheet.btn}></div>;
	assert renderToString(marked) === "<div class=\"x&amp;&quot;y " + (sheet.btn.cssId as string) + "\"></div>", "each class escaped once";
}

test "a sheet entry on a View serializes as a class, as it does on a tag" {
	resetCss();
	const html = renderToString(<View style={sheet.btn}><Text style={sheet.btn}>hi</Text></View>);
	const id = sheet.btn.cssId as string;
	assert html === "<div class=\"neon-view " + id + "\"><span class=\"neon-text " + id + "\">hi</span></div>", html;
}
