// Void host end-to-end: JSX counter → Scene2D rows held by VoidNode → flexbox layout →
// simulated click → reactive text update. Headless (no window) — the same
// pipeline the windowed example (examples/counterVoid.ms) runs per frame.

import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { render, HostNode } from "../../src/render/host";
import { createVoidHost, layoutPass, parseFlexStyle, VoidHost, VoidNode } from "../../src/platform/void/host";
import { Style } from "../../src/render/style";
import { NeonEvent } from "../../src/render/event";
import { Void, View, Text, ScrollView, Pressable } from "../../src/components/primitives";
import { HOST_MOVE_CONTRACT, RECONCILE_CONTRACT, hostMoveContract, reconcileContract } from "../render/hostContract";
import { FlexStyle } from "../../../yoga/src/index";
import {
	DrawKind, NodeRef, kind, text, paint, order, textStyle, local, content, scroll, numChildren, getChildAt, parent,
} from "../../../void/src/void2d/node";

function flexOf(n: VoidNode): FlexStyle { return n.flex as FlexStyle; }

function tapAt(vh: VoidHost, x: float32, y: float32): void {
	vh.clickAt(x, y);
	flush();
}

test "counter renders into the Void scene with parsed flex styles" {
	const [count, setCount] = createSignal(0);
	const app = element(
		<div style="flexDirection:column;width:200;height:120">
			<p style="height:20">Count: {count() + ""}</p>
			<button style="width:80;height:40" onPress={() => setCount(count() + 1)}>+</button>
		</div>
	);
	const vh = createVoidHost();
	render(app, vh.host, vh.root);

	assert (vh.root as VoidNode).children.length === 1, "root has the div";
	const div = (vh.root as VoidNode).children[0];
	assert div.ref.kind() === DrawKind.Group, "div is a group";
	assert div.children.length === 2, "div has p + button";

	const p = div.children[0];
	const button = div.children[1];
	assert p.ref.kind() === DrawKind.Group, "p is a group";
	assert p.children.length === 2, "p has a static and a dynamic text node";
	assert p.children[0].ref.kind() === DrawKind.Label, "text is a label";
	assert p.children[0].ref.text() === "Count: ", "static text";
	assert p.children[1].ref.text() === "0", "initial dyn text bound";
	assert button.children[0].ref.text() === "+", "button label";

	assert div.flex !== null, "div style parsed";
	assert button.flex !== null, "button style parsed";

	layoutPass(div, 200.0, 120.0);
	assert button.ref.content().w === 80.0, "button width from style";
	assert button.ref.content().h === 40.0, "button height from style";
	assert p.ref.local().y === 0.0, "p at top of column";
	assert button.ref.local().y === 20.0, "button below p";
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
	render(app, vh.host, vh.root);
	const div = (vh.root as VoidNode).children[0];
	layoutPass(div, 200.0, 120.0);

	const p = div.children[0];

	vh.clickAt(40.0, 40.0);
	flush();
	assert p.children[1].ref.text() === "1", "click inside button increments";

	vh.clickAt(150.0, 100.0);
	flush();
	assert p.children[1].ref.text() === "1", "click outside button is ignored";

	vh.clickAt(1.0, 21.0);
	flush();
	vh.clickAt(79.0, 59.0);
	flush();
	assert p.children[1].ref.text() === "3", "edge clicks inside bounds count";
}

test "parseFlexStyle maps numeric + enum keys and ignores junk" {
	const st = parseFlexStyle("width:320;flexGrow:1;flexDirection:row;justifyContent:center;alignItems:stretch;position:absolute;nonsense:42;broken");
	// PARKED as written on ~/metascript/.inbox/compiler/2026-10-03-nullish-coalesce-union-into-its-superset-rejected.md
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
	const n = node as VoidNode;
	assert n.ref.kind() === DrawKind.Group, "elements start as groups";
	vh.host.setStyle(node, { backgroundColor: "#3344ff", width: 100 } as Style);
	assert n.ref.kind() === DrawKind.Rect, "a group with a background must draw";
	assert n.ref.paint().color.b > 0.9, "blue channel came through";
	assert n.ref.paint().color.r < 0.3, "red channel stayed low";
}

test "setStyle: layout and paint are both applied, not one or the other" {
	const vh = createVoidHost();
	const node = vh.host.createElement("div");
	const n = node as VoidNode;
	vh.host.setStyle(node, { width: 64, opacity: 0.5, backgroundColor: "#ffffff" } as Style);
	assert n.flex !== null, "layout half reached yoga";
	assert n.ref.paint().alpha < 0.6, "paint half reached the node";
}

test "setStyle: text colour applies to labels" {
	const vh = createVoidHost();
	const node = vh.host.createText("hi");
	const n = node as VoidNode;
	vh.host.setStyle(node, { color: "#ff0000", fontSize: 24 } as Style);
	assert n.ref.paint().color.r > 0.9, "red text";
	assert n.ref.paint().color.g < 0.1, "no green";
	assert n.ref.textStyle().size > 23.0, "font size applied";
}

test "setStyle: a non-hex colour leaves the node untouched" {
	const vh = createVoidHost();
	const node = vh.host.createText("hi");
	const n = node as VoidNode;
	const before = n.ref.paint().color.r;
	vh.host.setStyle(node, { color: "rebeccapurple" } as Style);
	assert n.ref.paint().color.r === before, "unparseable colour is ignored, not zeroed";
}

test "setStyle: per-edge margin and padding reach yoga" {
	const vh = createVoidHost();
	const node = vh.host.createElement("div");
	const n = node as VoidNode;
	vh.host.setStyle(node, { marginTop: 8, marginLeft: 3, paddingLeft: 4, paddingBottom: 2 } as Style);
	assert flexOf(n).marginTop === 8, "marginTop reached yoga";
	assert flexOf(n).marginLeft === 3, "marginLeft reached yoga";
	assert flexOf(n).paddingLeft === 4, "paddingLeft reached yoga";
	assert flexOf(n).paddingBottom === 2, "paddingBottom reached yoga";
}

test "setStyle: min and max constraints reach yoga" {
	const vh = createVoidHost();
	const node = vh.host.createElement("div");
	const n = node as VoidNode;
	vh.host.setStyle(node, { minWidth: 10, maxHeight: 50, aspectRatio: 2 } as Style);
	assert flexOf(n).minWidth === 10, "minWidth reached yoga";
	assert flexOf(n).maxHeight === 50, "maxHeight reached yoga";
	assert flexOf(n).aspectRatio === 2, "aspectRatio reached yoga";
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
	const n = node as VoidNode;
	vh.host.setStyle(node, { flex: 1, flexBasis: 20, flexWrap: "wrap", alignSelf: "center", display: "none" } as Style);
	assert flexOf(n).flex === 1, "flex reached yoga";
	assert flexOf(n).flexBasis === 20, "flexBasis reached yoga";
	assert flexOf(n).flexWrap === "wrap", "flexWrap reached yoga";
	assert flexOf(n).alignSelf === "center", "alignSelf reached yoga";
	assert flexOf(n).display === "none", "display reached yoga";
}

test "setStyle: position fixed stays unset in yoga and absolute applies" {
	const vh = createVoidHost();
	const fixedNode = vh.host.createElement("div");
	vh.host.setStyle(fixedNode, { position: "fixed" } as Style);
	assert flexOf(fixedNode as VoidNode).position === null, "fixed is a position yoga cannot carry, so it stays unset";
	const absoluteNode = vh.host.createElement("div");
	vh.host.setStyle(absoluteNode, { position: "absolute" } as Style);
	assert flexOf(absoluteNode as VoidNode).position === "absolute", "absolute reached yoga";
}

test "setStyle: gap axes and border width reach yoga" {
	const vh = createVoidHost();
	const node = vh.host.createElement("div");
	const n = node as VoidNode;
	vh.host.setStyle(node, { rowGap: 6, columnGap: 9, borderWidth: 1 } as Style);
	assert flexOf(n).rowGap === 6, "rowGap reached yoga";
	assert flexOf(n).columnGap === 9, "columnGap reached yoga";
	assert flexOf(n).borderWidth === 1, "borderWidth reached yoga";
}

test "setStyle: overflow reaches yoga and zIndex reaches the node" {
	const vh = createVoidHost();
	const node = vh.host.createElement("div");
	const n = node as VoidNode;
	vh.host.setStyle(node, { overflow: "hidden", zIndex: 5 } as Style);
	assert flexOf(n).overflow === "hidden", "overflow reached yoga";
	assert n.ref.order().zIndex === 5, "zIndex reached the node";
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
	const st = flexOf(node as VoidNode);
	assert st.width === null, "width gone";
	assert st.flexGrow === null, "flexGrow gone";
	h.removeAttr(node, "title");
}

test "the void host opens no nested area, so a Void inside it fails and names the capability" {
	const vh = createVoidHost();
	assert vh.host.voidArea === null, "voidArea is null";
	let caught = "";
	try {
		render(element(<Void><View /></Void>), vh.host, vh.root);
	} catch (e) { caught = e.toString(); }
	assert caught.includes("voidArea"), "error names the capability: " + caught;
}

test "a HostNode cast back to VoidNode still reaches its row" {
	const vh = createVoidHost();
	const node = vh.host.createText("hi");
	const n = node as VoidNode;
	assert n.ref.text() === "hi", "the row holds the text";
	vh.host.setText(node, "yo");
	assert n.ref.text() === "yo", "setText wrote the row";
	assert (node as VoidNode) === n, "a cast hands back the same object";
	assert n.ref.scene === vh.scene, "the row lives in the host's scene";
}

test "a zIndex sibling keeps the Host move contract" {
	const got = hostMoveContract(createVoidHost().host, { zIndex: 5 } as Style);
	assert got === HOST_MOVE_CONTRACT, got;
}

test "removing a node frees its rows and a later op on it names itself" {
	const vh = createVoidHost();
	const before = vh.scene.nodeCount();
	render(element(<View><Text>a</Text><View /></View>), vh.host, vh.root);
	assert vh.scene.nodeCount() > before, "mounting made rows";
	const view = vh.host.firstChild(vh.root) as HostNode;
	const label = vh.host.firstChild(view) as HostNode;
	vh.host.removeChild(vh.root, view);
	assert vh.scene.nodeCount() === before, "removing freed every row of the subtree";
	let caught = "";
	try {
		vh.host.setText(label, "x");
	} catch (e) { caught = e.toString(); }
	assert caught.includes("setText"), "the error names the op: " + caught;
}

test "a background added after mount keeps children, order and handlers" {
	const vh = createVoidHost();
	let pressed = 0;
	const node = vh.host.createElement("view");
	const first = vh.host.createElement("view");
	const second = vh.host.createElement("view");
	vh.host.append(vh.root, node);
	vh.host.append(node, first);
	vh.host.append(node, second);
	vh.host.addEvent(node, "onPress", (e: NeonEvent): void => { pressed = pressed + 1; });
	vh.host.setStyle(node, { width: 100, height: 40 } as Style);
	vh.layout(100.0, 40.0);
	const n = node as VoidNode;
	const row = n.ref.id.index;
	assert n.ref.kind() === DrawKind.Group, "starts as a group";
	vh.host.setStyle(node, { width: 100, height: 40, backgroundColor: "#3344ff" } as Style);
	assert n.ref.kind() === DrawKind.Rect, "the background promoted the group";
	assert n.ref.id.index === row, "same row";
	assert n.ref.numChildren() === 2, "children kept";
	assert n.ref.getChildAt(0).id.index === (first as VoidNode).ref.id.index, "first child kept its place";
	assert n.ref.getChildAt(1).id.index === (second as VoidNode).ref.id.index, "second child kept its place";
	vh.clickAt(10.0, 10.0);
	flush();
	assert pressed === 1, "the handler survived";
	vh.host.setStyle(node, { width: 100, height: 40 } as Style);
	assert n.ref.kind() === DrawKind.Group, "dropping the background demoted it";
	assert n.ref.numChildren() === 2, "children kept through the demotion";
}

test "a click outside a scroll view's mask misses content it clips" {
	const vh = createVoidHost();
	let pressed = 0;
	render(element(
		<ScrollView style={{ width: 100, height: 50 }}>
			<Pressable style={{ width: 100, height: 200 }} onPress={(e: NeonEvent): void => { pressed = pressed + 1; }} />
		</ScrollView>
	), vh.host, vh.root);
	vh.layout(100.0, 50.0);
	tapAt(vh, 10.0, 120.0);
	assert pressed === 0, "content below the mask is clipped, so it is not hit";
	tapAt(vh, 10.0, 10.0);
	assert pressed === 1, "content inside the mask is hit";
}

test "a scroll view paints its background behind the content it scrolls" {
	const vh = createVoidHost();
	render(element(
		<ScrollView style={{ width: 100, height: 50, backgroundColor: "#203040" }}>
			<View style={{ width: 100, height: 200 }} />
		</ScrollView>
	), vh.host, vh.root);
	vh.layout(100.0, 50.0);
	const area = vh.host.firstChild(vh.root) as VoidNode;
	assert area.ref.kind() === DrawKind.Rect, "the scroll view's own box carries the background";
	const mask = area.scroller as NodeRef;
	assert mask.kind() === DrawKind.Mask, "the content sits in a mask inside it";
	assert mask.content().w === 100.0 && mask.content().h === 50.0, "the mask fills the scroll view";
	assert (area.children[0].ref.parent() as NodeRef).id === mask.id, "the child hangs under the mask";
	const scrollTo = vh.host.scrollTo as (node: HostNode, x: number, y: number, animated: boolean) => void;
	scrollTo(area, 0, 40, false);
	assert mask.scroll().y === 40.0, "the mask scrolled";
	assert area.ref.local().y === 0.0 && area.ref.kind() === DrawKind.Rect, "the background stayed put";
	vh.host.setStyle(area, { width: 100, height: 50 } as Style);
	assert area.ref.kind() === DrawKind.Group, "dropping the background demotes the box, not the mask";
}

test "scrollTo moves a scroll view and refuses a plain view by name" {
	const vh = createVoidHost();
	render(element(
		<ScrollView style={{ width: 100, height: 50 }}>
			<View style={{ width: 100, height: 200 }} />
		</ScrollView>
	), vh.host, vh.root);
	vh.layout(100.0, 50.0);
	const area = vh.host.firstChild(vh.root) as HostNode;
	const scrollTo = vh.host.scrollTo as (node: HostNode, x: number, y: number, animated: boolean) => void;
	scrollTo(area, 0, 40, false);
	const mask = (area as VoidNode).scroller as NodeRef;
	assert mask.scroll().y === 40.0, "the mask scrolled";
	scrollTo(area, 0, 900, true);
	assert mask.scroll().y === 150.0, "the offset stops at the end of the content";
	const plain = vh.host.createElement("view");
	let caught = "";
	try {
		scrollTo(plain, 0, 10, false);
	} catch (e) { caught = e.toString(); }
	assert caught.includes("scrollTo"), "the error names the op: " + caught;
}
