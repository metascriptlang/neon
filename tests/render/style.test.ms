// Typed style sheet → VNode.style → void host projection → yoga layout.
// S1 (docs/STYLE.md §9): static styles only — no variants, no layering, no
// reactive fields. The legacy string-attr path must keep working alongside it.

import { element } from "../../src/macros/ui/element";
import { el, attr, evt, text, dynText, withStyle } from "../../src/render/node";
import { renderToHost, HostNode } from "../../src/render/host";
import { createVoidHost, layoutPass } from "../../src/platform/void/host";
import { createStyles, styleOf } from "../../src/macros/ui/style";

const sheet = createStyles({
	box: { flexDirection: "column", width: 200, height: 120 },
	row: { height: 20 },
	btn: { width: 80, height: 40 },
});

test "typed style sheet drives void layout" {
	const app = element(
		<div style={sheet.box}>
			<p style={sheet.row}>Hi</p>
			<button style={sheet.btn}>+</button>
		</div>
	);
	const vh = createVoidHost();
	renderToHost(app, vh.host, vh.root as unknown as HostNode);

	const div = vh.root.children[0];
	assert div.children.length === 2, "div has p + button";
	const p = div.children[0];
	const button = div.children[1];

	assert div.layoutStyle !== null, "div style projected to FlexStyle";
	assert button.layoutStyle !== null, "button style projected to FlexStyle";

	layoutPass(div, 200.0, 120.0);
	assert button.w === 80.0, "button width from typed style";
	assert button.h === 40.0, "button height from typed style";
	assert p.y === 0.0, "p at top of column";
	assert button.y === 20.0, "button below p";
}

test "legacy string style attr still works" {
	const app = element(<div style="width:50;height:10"></div>);
	const vh = createVoidHost();
	renderToHost(app, vh.host, vh.root as unknown as HostNode);

	const div = vh.root.children[0];
	assert div.layoutStyle !== null, "string style still parsed";
	layoutPass(div, 50.0, 10.0);
	assert div.w === 50.0, "string style width survives";
}

test "inline style literal routes through the typed channel" {
	const app = element(<div style={{ width: 40, height: 10 }}></div>);
	const vh = createVoidHost();
	renderToHost(app, vh.host, vh.root as unknown as HostNode);
	const div = vh.root.children[0];
	assert div.layoutStyle !== null, "inline literal projected";
	layoutPass(div, 40.0, 10.0);
	assert div.w === 40.0, "inline width applies";
}

test "withStyle attaches a Style to a hand-built VNode" {
	const node = withStyle(el("div", [], [], []), sheet.btn);
	assert node.style !== null, "style slot set";
	assert el("div", [], [], []).style === null, "plain el has no style";
}
