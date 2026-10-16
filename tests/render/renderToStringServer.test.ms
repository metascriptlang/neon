import { NeonNode, el, text, attr, dynAttr, regionNode } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { Row, makeRow } from "../../src/render/reconcile";

function maybeClass(): string | null { return null; }

test "renderToString escapes text and quoted attributes" {
	const node = el("div", [attr("title", "\"' & < >")], [], text("<img src=x> &amp; café"));
	const expected = "<div title=\"&quot;&#39; &amp; &lt; &gt;\">" +
		"&lt;img src=x&gt; &amp;amp; café</div>";
	assert renderToString(node) === expected, renderToString(node);
	const edges = renderToString(el("p", [attr("title", "é'")], [], text("&é>")));
	assert edges === "<p title=\"é&#39;\">&amp;é&gt;</p>", edges;
	const clean = renderToString(el("p", [attr("title", "a-b c")], [], text("plain #1")));
	assert clean === "<p title=\"a-b c\">plain #1</p>", clean;
}

test "renderToString serializes a static tree" {
	const v: NeonNode = <div><p>hi</p></div>;
	assert renderToString(v) === "<div><p>hi</p></div>", "static serialize";
}

test "renderToString renders the rows of a region" {
	const rows: Row[] = [makeRow(<li>a</li>), makeRow(<li>b</li>)];
	const r = regionNode((h) => () => rows);
	assert renderToString(<ul>{r}</ul>) === "<ul><li>a</li><li>b</li><!----></ul>", renderToString(<ul>{r}</ul>);
}

test "renderToString leaves a null attr out" {
	const absent: string | null = null;
	const v: NeonNode = <div title={absent} id="x" class={maybeClass()}></div>;
	assert renderToString(v) === "<div id=\"x\"></div>", renderToString(v);
}
