// A snapshot render carries style the same way a mounted tree does
// (docs/STYLE.md §5): a static sheet entry becomes a class plus one rule in the
// registry, every other channel is written inline. Server markup that resolved
// styles differently from renderNode would hand the browser a tree it has to
// correct on hydration.
//
// Both lanes run this file: the js lane exercises the class route, the native
// lane pins that the same tree serializes inline, because the macro bakes no
// CSS metadata off the browser lane.

import { el, text, attr, withStyle, withDynStyle, withDynStyleAll, renderToString } from "../../src/render/node";
import { Style } from "../../src/render/style";
import { styleToCss } from "../../src/render/css";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { resetCss, cssRuleCount, mountSheet } from "../../src/render/sheet";
import { createSignal } from "../../src/core/signal";

const sheet = createStyles({
	btn: { padding: 8, backgroundColor: "#334" },
});

test "a static sheet entry serializes as a class and registers its rule" {
	resetCss();
	const html = renderToString(withStyle(el("div", [], [], [text("hi")]), sheet.btn));
	when (js) {
		const id = sheet.btn.cssId as string;
		assert html === "<div class=\"" + id + "\">hi</div>", "class, no inline copy of the rule";
		assert cssRuleCount() === 1, "rendering the node mounted the rule";
		assert mountSheet() === "<style>." + id + "{padding:8px;background-color:#334;}</style>", "the page emits the whole registry in one block";
	} else {
		assert html === "<div style=\"padding:8px;background-color:#334;\">hi</div>", "no css metadata off the browser lane, so the fields go inline";
		assert cssRuleCount() === 0, "and nothing reaches the registry";
	}
}

test "the runtime spelling equals the rule the macro baked" {
	when (js) {
		assert (sheet.btn.css as string) === "." + (sheet.btn.cssId as string) + "{" + styleToCss(sheet.btn) + "}", "one vocabulary, two spellings, same text";
	}
}

test "an inline style literal serializes into the style attribute" {
	const s = styleOf({ width: "50%", opacity: 0.5, color: "#fff" });
	assert renderToString(withStyle(el("p", [], [], []), s)) === "<p style=\"width:50%;opacity:0.5;color:#fff;\"></p>", "a string dimension passes through, a ratio takes no unit";
}

test "a reactive whole-style thunk serializes its value at render time" {
	const [w, setW] = createSignal(10);
	const n = withDynStyleAll(el("div", [], [], []), () => styleOf({ width: w() }) as Style);
	assert renderToString(n) === "<div style=\"width:10px;\"></div>", "the thunk runs";
	setW(20);
	assert renderToString(n) === "<div style=\"width:20px;\"></div>", "a second render re-reads it";
}

test "per-property thunks land over the static base" {
	const n = withDynStyle(withStyle(el("div", [], [], []), styleOf({ padding: 4 })), "width", () => 7);
	assert renderToString(n) === "<div style=\"width:7px;padding:4px;\"></div>", "declaration order, base and override together";
}

test "a class from a sheet joins the class attribute already on the node" {
	when (js) {
		const n = withStyle(el("div", [attr("class", "x")], [], []), sheet.btn);
		assert renderToString(n) === "<div class=\"x " + (sheet.btn.cssId as string) + "\"></div>", "one class attribute, not two";
	}
}

test "an empty registry emits no style block" {
	resetCss();
	assert mountSheet() === "", "nothing registered, nothing printed";
}
