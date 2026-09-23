// Void host end-to-end: JSX counter → Node2D scene graph → flexbox layout →
// simulated click → reactive text update. Headless (no window) — the same
// pipeline the windowed example (examples/counterVoid.ms) runs per frame.

import { createSignal } from "../../src/core/signal";
import { el, attr, evt, text, dynText } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { render, HostNode } from "../../src/render/host";
import { createVoidHost, layoutPass, parseFlexStyle, DrawKind, Node2D } from "../../src/platform/void/host";
import { Style } from "../../src/render/style";
import { HOST_MOVE_CONTRACT, RECONCILE_CONTRACT, hostMoveContract, reconcileContract } from "../render/hostContract";

test "counter renders into Node2D tree with parsed flex styles" {
	const [count, setCount] = createSignal(0);
	const app = element(
		<div style="flexDirection:column;width:200;height:120">
			<p style="height:20">Count: {count() + ""}</p>
			<button style="width:80;height:40" onPress={() => setCount(count() + 1)}>+</button>
		</div>
	);
	const vh = createVoidHost();
	render(app, vh.host, vh.root as unknown as HostNode);

	assert vh.root.children.length === 1, "root has the div";
	const div = vh.root.children[0];
	assert div.kind === DrawKind.Group, "div is a group";
	assert div.children.length === 2, "div has p + button";

	const p = div.children[0];
	const button = div.children[1];
	assert p.kind === DrawKind.Group, "p is a group";
	assert p.children.length === 2, "p has a static and a dynamic text node";
	assert p.children[0].kind === DrawKind.Label, "text is a label";
	assert p.children[0].text === "Count: ", "static text";
	assert p.children[1].text === "0", "initial dyn text bound";
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
			<button style="width:80;height:40" onPress={() => setCount(count() + 1)}>+</button>
		</div>
	);
	const vh = createVoidHost();
	render(app, vh.host, vh.root as unknown as HostNode);
	const div = vh.root.children[0];
	layoutPass(div, 200.0, 120.0);

	const p = div.children[0];

	vh.clickAt(40.0, 40.0);
	assert p.children[1].text === "1", "click inside button increments";

	vh.clickAt(150.0, 100.0);
	assert p.children[1].text === "1", "click outside button is ignored";

	vh.clickAt(1.0, 21.0);
	vh.clickAt(79.0, 59.0);
	assert p.children[1].text === "3", "edge clicks inside bounds count";
}

test "parseFlexStyle maps numeric + enum keys and ignores junk" {
	const st = parseFlexStyle("width:320;flexGrow:1;flexDirection:row;justifyContent:center;alignItems:stretch;position:absolute;nonsense:42;broken");
	assert (st.width ?? 0.0) === 320.0, "width parsed as points";
	assert (st.flexGrow ?? 0.0) === 1.0, "flexGrow parsed";
	assert (st.flexDirection ?? "column") === "row", "flexDirection parsed";
	assert (st.justifyContent ?? "flex-start") === "center", "justifyContent parsed";
	assert (st.alignItems ?? "auto") === "stretch", "alignItems parsed";
	assert (st.position ?? "static") === "absolute", "position parsed";
	assert st.height === null, "unset stays null";
}

// ===== S2: the paint half of the Style projection (docs/STYLE.md §5) =====

test "setStyle: a background turns a group into a drawable rect" {
	const vh = createVoidHost();
	const node = vh.host.createElement("div");
	const n = node as unknown as Node2D;
	assert n.kind === DrawKind.Group, "elements start as groups";
	vh.host.setStyle(node, { backgroundColor: "#3344ff", width: 100 } as Style);
	assert n.kind === DrawKind.Rect, "a group with a background must draw";
	assert n.color.b > 0.9, "blue channel came through";
	assert n.color.r < 0.3, "red channel stayed low";
}

test "setStyle: layout and paint are both applied, not one or the other" {
	const vh = createVoidHost();
	const node = vh.host.createElement("div");
	const n = node as unknown as Node2D;
	vh.host.setStyle(node, { width: 64, opacity: 0.5, backgroundColor: "#ffffff" } as Style);
	assert n.layoutStyle !== null, "layout half reached yoga";
	assert n.alpha < 0.6, "paint half reached the node";
}

test "setStyle: text colour applies to labels" {
	const vh = createVoidHost();
	const node = vh.host.createText("hi");
	const n = node as unknown as Node2D;
	vh.host.setStyle(node, { color: "#ff0000", fontSize: 24 } as Style);
	assert n.color.r > 0.9, "red text";
	assert n.color.g < 0.1, "no green";
	assert n.size > 23.0, "font size applied";
}

test "setStyle: a non-hex colour leaves the node untouched" {
	const vh = createVoidHost();
	const node = vh.host.createText("hi");
	const n = node as unknown as Node2D;
	const before = n.color.r;
	vh.host.setStyle(node, { color: "rebeccapurple" } as Style);
	assert n.color.r === before, "unparseable colour is ignored, not zeroed";
}

test "setStyle: per-edge margin and padding reach yoga" {
	const vh = createVoidHost();
	const node = vh.host.createElement("div");
	const n = node as unknown as Node2D;
	vh.host.setStyle(node, { marginTop: 8, marginLeft: 3, paddingLeft: 4, paddingBottom: 2 } as Style);
	assert n.layoutStyle.marginTop === 8, "marginTop reached yoga";
	assert n.layoutStyle.marginLeft === 3, "marginLeft reached yoga";
	assert n.layoutStyle.paddingLeft === 4, "paddingLeft reached yoga";
	assert n.layoutStyle.paddingBottom === 2, "paddingBottom reached yoga";
}

test "setStyle: min and max constraints reach yoga" {
	const vh = createVoidHost();
	const node = vh.host.createElement("div");
	const n = node as unknown as Node2D;
	vh.host.setStyle(node, { minWidth: 10, maxHeight: 50, aspectRatio: 2 } as Style);
	assert n.layoutStyle.minWidth === 10, "minWidth reached yoga";
	assert n.layoutStyle.maxHeight === 50, "maxHeight reached yoga";
	assert n.layoutStyle.aspectRatio === 2, "aspectRatio reached yoga";
}

test "setStyle: a percent dimension is refused and names the field" {
	const vh = createVoidHost();
	const node = vh.host.createElement("div");
	let caught = "";
	try {
		vh.host.setStyle(node, { maxHeight: "50%" } as Style);
	} catch (e) { caught = e.toString(); }
	assert caught.includes("maxHeight") && caught.includes("50%"), "error names field and value: " + caught;
}

test "setStyle: flex shorthand, basis, wrap and self-alignment reach yoga" {
	const vh = createVoidHost();
	const node = vh.host.createElement("div");
	const n = node as unknown as Node2D;
	vh.host.setStyle(node, { flex: 1, flexBasis: 20, flexWrap: "wrap", alignSelf: "center", display: "none" } as Style);
	assert n.layoutStyle.flex === 1, "flex reached yoga";
	assert n.layoutStyle.flexBasis === 20, "flexBasis reached yoga";
	assert n.layoutStyle.flexWrap === "wrap", "flexWrap reached yoga";
	assert n.layoutStyle.alignSelf === "center", "alignSelf reached yoga";
	assert n.layoutStyle.display === "none", "display reached yoga";
}

test "setStyle: gap axes and border width reach yoga" {
	const vh = createVoidHost();
	const node = vh.host.createElement("div");
	const n = node as unknown as Node2D;
	vh.host.setStyle(node, { rowGap: 6, columnGap: 9, borderWidth: 1 } as Style);
	assert n.layoutStyle.rowGap === 6, "rowGap reached yoga";
	assert n.layoutStyle.columnGap === 9, "columnGap reached yoga";
	assert n.layoutStyle.borderWidth === 1, "borderWidth reached yoga";
}

test "setStyle: overflow reaches yoga and zIndex reaches the node" {
	const vh = createVoidHost();
	const node = vh.host.createElement("div");
	const n = node as unknown as Node2D;
	vh.host.setStyle(node, { overflow: "hidden", zIndex: 5 } as Style);
	assert n.layoutStyle.overflow === "hidden", "overflow reached yoga";
	assert n.zIndex === 5, "zIndex reached the node";
}

test "the void host keeps the DOM move contract" {
	const got = hostMoveContract(createVoidHost().host);
	assert got === HOST_MOVE_CONTRACT, got;
}

test "reconcileArrays keeps its contract on the void host" {
	const got = reconcileContract(createVoidHost().host);
	assert got === RECONCILE_CONTRACT, got;
}

test "void removeAttr on style drops the parsed layout" {
	const h = createVoidHost().host;
	const node = h.createElement("view");
	h.setAttr(node, "style", "width:320;flexGrow:1");
	h.removeAttr(node, "style");
	const st = (node as unknown as Node2D).layoutStyle;
	assert st.width === null, "width gone";
	assert st.flexGrow === null, "flexGrow gone";
	h.removeAttr(node, "title");
}
