import { el, text, attr, dynAttr, regionNode, renderToString } from "../../src/render/node";

test "renderToString serializes a static tree" {
	const v = el("div", [], [], [el("p", [], [], [text("hi")])]);
	assert renderToString(v) === "<div><p>hi</p></div>", "static serialize";
}

test "renderToString rejects a region node instead of silently emptying" {
	let threw = false;
	const r = regionNode((h) => () => [] as unknown[]);
	try {
		renderToString(r);
	} catch (e) {
		threw = true;
	}
	assert threw, "region must throw";
}

test "renderToString leaves a null attr out" {
	const v = el("div", [attr("title", null), attr("id", "x"), dynAttr("class", () => null)], [], []);
	assert renderToString(v) === "<div id=\"x\"></div>", renderToString(v);
}
