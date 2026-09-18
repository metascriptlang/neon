import { NeonNode, el, text, attr, dynAttr, regionNode, renderToString } from "../../src/render/node";

function maybeClass(): string | null { return null; }

test "renderToString serializes a static tree" {
	const v: NeonNode = <div><p>hi</p></div>;
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
	const absent: string | null = null;
	const v: NeonNode = <div title={absent} id="x" class={maybeClass()}></div>;
	assert renderToString(v) === "<div id=\"x\"></div>", renderToString(v);
}
