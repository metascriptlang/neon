import { NeonNode, el, text, attr, dynAttr, regionNode } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { Row, makeRow } from "../../src/render/reconcile";

function maybeClass(): string | null { return null; }

test "renderToString serializes a static tree" {
	const v: NeonNode = <div><p>hi</p></div>;
	assert renderToString(v) === "<div><p>hi</p></div>", "static serialize";
}

test "renderToString renders the rows of a region" {
	const rows: Row[] = [makeRow(<li>a</li>), makeRow(<li>b</li>)];
	const r = regionNode((h) => () => rows);
	assert renderToString(<ul>{r}</ul>) === "<ul><li>a</li><li>b</li></ul>", renderToString(<ul>{r}</ul>);
}

test "renderToString leaves a null attr out" {
	const absent: string | null = null;
	const v: NeonNode = <div title={absent} id="x" class={maybeClass()}></div>;
	assert renderToString(v) === "<div id=\"x\"></div>", renderToString(v);
}
