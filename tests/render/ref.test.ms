// ref â€” the escape hatch to the host node. The callback fires once per mount
// with the node the element became.
//
// ref — the escape hatch to the host node, and Solid 2.0's directive surface
// (docs/SOLID.md "Refs and directives"). A ref runs after its element's attributes and
// before its children, a parent's before a child's, and always before the site root is
// placed. `ref={[a, b]}` applies in source order; a call such as `ref={tooltip(opts)}` is
// a directive factory whose setup runs in the current owner and whose returned function
// is the apply phase.

import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { onCleanup } from "../../src/core/cleanup";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent } from "../../src/render/host";
import { View, TextInput, TextInputHandle, Pressable, Text } from "../../src/components/primitives";
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
	const grabInput = (h: TextInputHandle): void => { inputTag = (h.node as unknown as MockNode).tag; };
	const root: MockNode = mockNode("root");
	render(element(<View ref={grabView}><TextInput ref={grabInput} /></View>), mockHost(), root as unknown as HostNode);
	assert viewTag === "view", "View ref, tag=" + viewTag;
	assert inputTag === "textinput", "TextInput ref, tag=" + inputTag;
}

test "ref fires before a reactive child is bound" {
	const [n, _setN] = createSignal(7);
	let seen = "";
	const grab: (h: HostNode) => void = (h) => { seen = mockToString(h as unknown as MockNode); };
	const root: MockNode = mockNode("root");
	render(element(<p ref={grab}>{n().toString()}</p>), mockHost(), root as unknown as HostNode);
	assert seen === "<p></p>", "ref saw the node before its reactive child, seen=" + seen;
	assert mockToString(root) === "<root><p>7</p></root>", "the child is bound afterwards: " + mockToString(root);
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

test "nested refs fire outermost first, in the template path" {
	let order = "";
	const root: MockNode = mockNode("root");
	const outer: (h: HostNode) => void = (h) => { order = order + "outer"; };
	const inner: (h: HostNode) => void = (h) => { order = order + "inner"; };
	render(element(<div ref={outer}><p ref={inner}>hi</p></div>), mockHost(), root as unknown as HostNode);
	assert order === "outerinner", "order=" + order;
}

test "a ref runs after the attributes and before the children, in the flat path" {
	const [n, _setN] = createSignal("a");
	let seen = "";
	let order = "";
	const root: MockNode = mockNode("root");
	const outer: (h: HostNode) => void = (h) => { order = order + "outer"; seen = mockToString(h as unknown as MockNode); };
	const inner: (h: HostNode) => void = (h) => { order = order + "inner"; };
	render(element(<div class="box" title={n()} ref={outer}><View ref={inner}><Text>x</Text></View></div>), mockHost(), root as unknown as HostNode);
	assert seen === "<div class=\"box\" title=\"a\"></div>", "attributes set, no child yet: " + seen;
	assert order === "outerinner", "order=" + order;
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

function stamp(log: string[], name: string): (h: HostNode) => void {
	return (h: HostNode): void => { log.push(name); };
}

test "ref={[a, b]} applies in source order, flattening nested arrays and nulls" {
	const log: string[] = [];
	const none: ((h: HostNode) => void) | null = null;
	const root: MockNode = mockNode("root");
	render(element(<p ref={[stamp(log, "a"), [stamp(log, "b"), none], stamp(log, "c")]}>hi</p>), mockHost(), root as unknown as HostNode);
	assert log.join(",") === "a,b,c", "order=" + log.join(",");
}

test "ref arrays work in the flat path and on a component" {
	const log: string[] = [];
	const root: MockNode = mockNode("root");
	render(element(<div ref={[stamp(log, "d1"), stamp(log, "d2")]}><View ref={[stamp(log, "v1"), stamp(log, "v2")]}><Text>x</Text></View></div>), mockHost(), root as unknown as HostNode);
	assert log.join(",") === "d1,d2,v1,v2", "order=" + log.join(",");
}

test "a typed handle ref takes an array" {
	const log: string[] = [];
	const a = (h: TextInputHandle): void => { log.push("a"); };
	const b = (h: TextInputHandle): void => { log.push("b"); };
	const root: MockNode = mockNode("root");
	render(element(<TextInput ref={[a, b]} />), mockHost(), root as unknown as HostNode);
	assert log.join(",") === "a,b", "order=" + log.join(",");
}

test "ref apply is untracked: a signal read in it does not re-run the mount" {
	const [n, setN] = createSignal(0);
	let mounts = 0;
	const read: (h: HostNode) => void = (h) => { n(); };
	const root: MockNode = mockNode("root");
	createRoot((dispose) => {
		createEffect(() => {
			mounts = mounts + 1;
			element(<p ref={read}>hi</p>)(mockHost(), root as unknown as HostNode, null);
		});
		return 0;
	});
	setN(1);
	assert mounts === 1, "mounts=" + mounts.toString();
}

function tooltip(log: string[], source: () => number): (h: HostNode) => void {
	createEffect(() => { log.push("effect" + source().toString()); });
	onCleanup(() => { log.push("cleanup"); });
	return (h: HostNode): void => { log.push("apply" + source().toString()); };
}

test "a directive factory sets up in the current owner and applies as the returned function" {
	const [n, setN] = createSignal(1);
	const log: string[] = [];
	const root: MockNode = mockNode("root");
	const read = (): number => n();
	const dispose = render(element(<p ref={tooltip(log, read)}>hi</p>), mockHost(), root as unknown as HostNode);
	assert log.join(",") === "effect1,apply1", "setup before apply: " + log.join(",");
	setN(2);
	assert log.join(",") === "effect1,apply1,effect2", "the setup effect lives on, the apply does not rerun: " + log.join(",");
	dispose();
	assert log.join(",") === "effect1,apply1,effect2,cleanup", "the owner's disposal runs the setup cleanup: " + log.join(",");
}

function readingFactory(source: () => number): (h: HostNode) => void {
	source();
	return (h: HostNode): void => {};
}

test "a directive factory sets up untracked: a signal read in setup does not re-run the mount" {
	const [n, setN] = createSignal(0);
	let mounts = 0;
	const read = (): number => n();
	const root: MockNode = mockNode("root");
	createRoot((dispose) => {
		createEffect(() => {
			mounts = mounts + 1;
			element(<p ref={readingFactory(read)}>hi</p>)(mockHost(), root as unknown as HostNode, null);
		});
		return 0;
	});
	setN(1);
	assert mounts === 1, "mounts=" + mounts.toString();
}

test "an array mixes a factory and a plain callback" {
	const log: string[] = [];
	const [n, _setN] = createSignal(5);
	const read = (): number => n();
	const root: MockNode = mockNode("root");
	render(element(<p ref={[tooltip(log, read), stamp(log, "plain")]}>hi</p>), mockHost(), root as unknown as HostNode);
	assert log.join(",") === "effect5,apply5,plain", "order=" + log.join(",");
}

test "a cleanup registered in the apply phase belongs to the mounting owner" {
	const log: string[] = [];
	const grab: (h: HostNode) => void = (h) => { onCleanup(() => { log.push("apply cleanup"); }); };
	const root: MockNode = mockNode("root");
	const dispose = render(element(<p ref={grab}>hi</p>), mockHost(), root as unknown as HostNode);
	assert log.length === 0, "not yet";
	dispose();
	assert log.join(",") === "apply cleanup", log.join(",");
}
