// Void host end-to-end: JSX counter → Node2D scene graph → flexbox layout →
// simulated click → reactive text update. Headless (no window) — the same
// pipeline the windowed example (examples/counterVoid.ms) runs per frame.

import { createSignal } from "../../src/core/signal";
import { el, attr, evt, text, dynText } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { renderToHost, HostNode } from "../../src/render/host";
import { createVoidHost, layoutPass, parseFlexStyle, DrawKind, Node2D } from "../../src/platform/void/host";

test "counter renders into Node2D tree with parsed flex styles" {
	const [count, setCount] = createSignal(0);
	const app = element(
		<div style="flexDirection:column;width:200;height:120">
			<p style="height:20">Count: {count() + ""}</p>
			<button style="width:80;height:40" onClick={() => setCount(count() + 1)}>+</button>
		</div>
	);
	const vh = createVoidHost();
	renderToHost(app, vh.host, vh.root as unknown as HostNode);

	assert vh.root.children.length === 1, "root has the div";
	const div = vh.root.children[0];
	assert div.kind === DrawKind.Group, "div is a group";
	assert div.children.length === 2, "div has p + button";

	const p = div.children[0];
	const button = div.children[1];
	assert p.kind === DrawKind.Group, "p is a group";
	assert p.children.length === 1, "p has one text node";
	assert p.children[0].kind === DrawKind.Label, "text is a label";
	assert p.children[0].text === "Count: 0", "initial dyn text bound";
	assert button.children[0].text === "+", "button label";

	assert div.layoutStyle !== null, "div style parsed";
	assert button.layoutStyle !== null, "button style parsed";

	layoutPass(div, 200.0, 120.0);
	assert button.w === 80.0, "button width from style";
	assert button.h === 40.0, "button height from style";
	assert p.y === 0.0, "p at top of column";
	assert button.y === 20.0, "button below p";
}

test "clickAt hits the button and reactive text updates" {
	const [count, setCount] = createSignal(0);
	const app = element(
		<div style="flexDirection:column;width:200;height:120">
			<p style="height:20">Count: {count() + ""}</p>
			<button style="width:80;height:40" onClick={() => setCount(count() + 1)}>+</button>
		</div>
	);
	const vh = createVoidHost();
	renderToHost(app, vh.host, vh.root as unknown as HostNode);
	const div = vh.root.children[0];
	layoutPass(div, 200.0, 120.0);

	const textNode = div.children[0].children[0];

	vh.clickAt(40.0, 40.0);
	assert textNode.text === "Count: 1", "click inside button increments";

	vh.clickAt(150.0, 100.0);
	assert textNode.text === "Count: 1", "click outside button is ignored";

	vh.clickAt(1.0, 21.0);
	vh.clickAt(79.0, 59.0);
	assert textNode.text === "Count: 3", "edge clicks inside bounds count";
}

test "parseFlexStyle maps numeric + enum keys and ignores junk" {
	const st = parseFlexStyle("width:320;flexGrow:1;flexDirection:row;justifyContent:center;alignItems:stretch;position:absolute;nonsense:42;broken");
	assert st.width === 320.0, "width parsed";
	assert st.flexGrow === 1.0, "flexGrow parsed";
	assert st.flexDirection === "row", "flexDirection parsed";
	assert st.justifyContent === "center", "justifyContent parsed";
	assert st.alignItems === "stretch", "alignItems parsed";
	assert st.position === "absolute", "position parsed";
	assert st.height === null, "unset stays null";
}
