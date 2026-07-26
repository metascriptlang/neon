import { el, text, regionNode, renderToString } from "../../src/render/node";

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
