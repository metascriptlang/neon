// ref — the escape hatch to the host node. The callback fires once per mount
// with the node the element became.
//
// Ordering follows REACT, not Solid, decided 2026-09-18 after reading both: ref is
// component/event surface, and the standing rule is reactivity = Solid, component and
// event surface = React Native. React attaches refs innermost-first, after the subtree
// is built (`~/projects/react/packages/react-reconciler/src/ReactFiberCommitWork.js`:
// recursivelyTraverseLayoutEffects `:682` `:627` before safelyAttachRef `:700` `:641`).
// Solid is the one that differs — dom-expressions unshifts `use(ref, el)` onto the
// element's own exprs (`packages/babel-plugin-jsx-dom-expressions/src/dom/element.js`
// `:676` `:694` `:704`) while transformChildren pushes each child's afterwards
// (`:1122`), so a parent's ref runs BEFORE any child's. The cells below pin React's
// order: innermost-first, and a ref already sees a bound reactive child. What all three
// agree on: ref fires before the site root is placed.

import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent } from "../../src/render/host";
import { View, TextInput, Pressable, Text } from "../../src/components/primitives";
import { NeonEvent } from "../../src/render/event";

test "ref hands the completed host node to the callback" {
	let seen = "";
	const grab: (n: HostNode) => void = (n) => { seen = mockToString(n as unknown as MockNode); };
	const root: MockNode = mockNode("root");
	const view: NeonNode = element(<div class="box"><p ref={grab}>hi</p></div>);
	render(view, mockHost(), root as unknown as HostNode);
	assert seen === "<p>hi</p>", "ref saw the finished node, seen=" + seen;
	assert mockToString(root) === "<root><div class=\"box\"><p>hi</p></div></root>", "ref leaves no attribute behind: " + mockToString(root);
}

test "ref on the root element of a site" {
	let tag = "";
	const grab: (n: HostNode) => void = (n) => { tag = (n as unknown as MockNode).tag; };
	const root: MockNode = mockNode("root");
	render(element(<section ref={grab}>x</section>), mockHost(), root as unknown as HostNode);
	assert tag === "section", "root ref, tag=" + tag;
	assert mockToString(root) === "<root><section>x</section></root>", "golden: " + mockToString(root);
}

test "ref reaches the universal vocabulary, not just raw tags" {
	let viewTag = "";
	let inputTag = "";
	const grabView: (n: HostNode) => void = (n) => { viewTag = (n as unknown as MockNode).tag; };
	const grabInput: (n: HostNode) => void = (n) => { inputTag = (n as unknown as MockNode).tag; };
	const root: MockNode = mockNode("root");
	render(element(<View ref={grabView}><TextInput ref={grabInput} /></View>), mockHost(), root as unknown as HostNode);
	assert viewTag === "view", "View ref, tag=" + viewTag;
	assert inputTag === "textinput", "TextInput ref, tag=" + inputTag;
}

test "ref fires after a reactive child is bound" {
	const [n, _setN] = createSignal(7);
	let seen = "";
	const grab: (h: HostNode) => void = (h) => { seen = mockToString(h as unknown as MockNode); };
	const root: MockNode = mockNode("root");
	render(element(<p ref={grab}>{n().toString()}</p>), mockHost(), root as unknown as HostNode);
	assert seen === "<p>7</p>", "ref saw the bound child, seen=" + seen;
}

test "a callback prop crosses raw when it is named, not only when it is a literal" {
	let hits = 0;
	const inc: (e: NeonEvent) => void = (e) => { hits = hits + 1; };
	let seenTag = "";
	const grab: (h: HostNode) => void = (h) => { seenTag = (h as unknown as MockNode).tag; };
	const root: MockNode = mockNode("root");
	render(element(<Pressable onPress={inc} ref={grab}><Text>+</Text></Pressable>), mockHost(), root as unknown as HostNode);
	fireEvent(root.children[0], "onPress");
	assert hits === 1, "named handler ran, hits=" + hits.toString();
	assert seenTag === "pressable", "named ref ran, tag=" + seenTag;
}

test "an inline arrow ref crosses raw" {
	let seen = "";
	const root: MockNode = mockNode("root");
	render(element(<p ref={(n: HostNode) => { seen = (n as unknown as MockNode).tag; }}>hi</p>), mockHost(), root as unknown as HostNode);
	assert seen === "p", "inline arrow ref fired, seen=" + seen;
}

test "ref fires before the site root is placed" {
	const root: MockNode = mockNode("root");
	let kidsAtRef = -1;
	const grab: (h: HostNode) => void = (h) => { kidsAtRef = root.children.length; };
	render(element(<div ref={grab}><p>hi</p></div>), mockHost(), root as unknown as HostNode);
	assert kidsAtRef === 0, "ref ran before the root was placed, kids=" + kidsAtRef.toString();
}

test "nested refs fire innermost first, each with its own children complete" {
	let order = "";
	const root: MockNode = mockNode("root");
	const outer: (h: HostNode) => void = (h) => { order = order + "outer" + (h as unknown as MockNode).children.length.toString(); };
	const inner: (h: HostNode) => void = (h) => { order = order + "inner" + (h as unknown as MockNode).children.length.toString(); };
	render(element(<div ref={outer}><p ref={inner}>hi</p></div>), mockHost(), root as unknown as HostNode);
	assert order === "inner1outer1", "order=" + order;
}

test "a nested ref sees its parent inside the template" {
	let parentTag = "?";
	const root: MockNode = mockNode("root");
	const grab: (h: HostNode) => void = (h) => {
		const p = (h as unknown as MockNode).parent;
		parentTag = p === null ? "<none>" : p.tag;
	};
	render(element(<div><p ref={grab}>hi</p></div>), mockHost(), root as unknown as HostNode);
	assert parentTag === "div", "nested ref sees its parent, parent=" + parentTag;
}
