// `{...props}` on a host tag, decided at compile time from the spread
// expression's TYPE: every field becomes the same channel its explicit twin
// would (attr / dynAttr / evt / style / ref), a later prop beats an earlier one
// while keeping the earlier one's position (setAttribute semantics,
// HOST_ATTR_CONTRACT), null removes, and an Accessor field stays reactive.

import { createSignal, Accessor, accessor } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { NeonEvent } from "../../src/render/event";
import { render, mockHost, mockNode, mockToString, fireEvent, HostNode, MockNode } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { styleToCss } from "../../src/render/css";
import { flush } from "../../src/core/runtime";

interface Attrs {
	id: string;
	title: string | null;
}

interface Reactive {
	title: Accessor<string>;
}

interface Styled {
	style: Style;
}

interface Handlers {
	onPress: (e: NeonEvent) => void;
}

test "a spread inside a container element expands the same way" {
	const p = { id: "x" };
	const flag = true;
	const n: NeonNode = element(<div>{flag ? <span {...p}>hi</span> : null}</div>);
	const host = mockHost();
	const root = mockNode("root");
	render(n, host, root as unknown as HostNode);
	assert mockToString(root.children[0]) === "<div><span id=\"x\">hi</span></div>", "nested spread expands";
}

test "a null field removes an attribute already written by an earlier prop" {
	function view(p: Attrs): NeonNode {
		return element(<div title="early" {...p}>hi</div>);
	}
	const host = mockHost();
	const root = mockNode("root");
	render(view({ id: "x", title: null }), host, root as unknown as HostNode);
	assert mockToString(root.children[0]) === "<div id=\"x\">hi</div>", "null erases the earlier title";
}

test "an on* field becomes an event" {
	let hits = 0;
	function view(p: Handlers): NeonNode {
		return element(<div {...p}>hi</div>);
	}
	const host = mockHost();
	const root = mockNode("root");
	render(view({ onPress: (e: NeonEvent) => { hits = hits + 1; } }), host, root as unknown as HostNode);
	fireEvent(root.children[0], "onPress");
	flush();
	assert hits === 1, "spread handler fired";
}

test "attrs on both sides of a spread each keep their own position" {
	const p = { id: "x", title: "t" };
	const host = mockHost();
	const root = mockNode("root");
	render(element(<div title="early" {...p} id="late">hi</div>), host, root as unknown as HostNode);
	assert mockToString(root.children[0]) === "<div title=\"t\" id=\"late\">hi</div>", "override order: " + mockToString(root.children[0]);
}

test "an Accessor field updates the attribute of a mounted node" {
	const [t, setT] = createSignal("a");
	function view(p: Reactive): NeonNode {
		return element(<div {...p}>hi</div>);
	}
	const host = mockHost();
	const root = mockNode("root");
	render(view({ title: t }), host, root as unknown as HostNode);
	assert mockToString(root.children[0]) === "<div title=\"a\">hi</div>", "initial: " + mockToString(root.children[0]);
	setT("b");
	flush();
	assert mockToString(root.children[0]) === "<div title=\"b\">hi</div>", "after set: " + mockToString(root.children[0]);
}

function mounted(view: NeonNode): MockNode {
	const root = mockNode("root");
	render(view, mockHost(), root as unknown as HostNode);
	return root;
}

function styleOf(div: MockNode): string {
	return div.style === null ? "(none)" : styleToCss(div.style as Style);
}

test "an object literal spread contributes one attr per field" {
	const p = { id: "x", title: "t" };
	const root = mounted(element(<div {...p}>hi</div>));
	assert mockToString(root) === "<root><div id=\"x\" title=\"t\">hi</div></root>", "both fields land as attrs: " + mockToString(root);
}

test "an explicit attr after a spread wins and keeps the spread's position" {
	const p = { id: "x", title: "t" };
	const root = mounted(element(<div {...p} id="late">hi</div>));
	assert mockToString(root) === "<root><div id=\"late\" title=\"t\">hi</div></root>", "later explicit attr wins in place: " + mockToString(root);
}

test "a spread after an explicit attr wins" {
	const p = { id: "x" };
	const root = mounted(element(<div id="early" class="c" {...p}>hi</div>));
	assert mockToString(root) === "<root><div id=\"x\" class=\"c\">hi</div></root>", "later spread wins in place: " + mockToString(root);
}

test "the later of two spreads wins" {
	const a = { id: "a", title: "ta" };
	const b = { id: "b" };
	const root = mounted(element(<div {...a} {...b}>hi</div>));
	assert mockToString(root) === "<root><div id=\"b\" title=\"ta\">hi</div></root>", "second spread overrides the first: " + mockToString(root);
}

test "a null field removes the attribute" {
	function view(p: Attrs): NeonNode {
		return element(<div {...p}>hi</div>);
	}
	const absent = mounted(view({ id: "x", title: null }));
	assert mockToString(absent) === "<root><div id=\"x\">hi</div></root>", "null field is absent: " + mockToString(absent);
	const present = mounted(view({ id: "x", title: "t" }));
	assert mockToString(present) === "<root><div id=\"x\" title=\"t\">hi</div></root>", "set field is present: " + mockToString(present);
}

test "a style field replaces an earlier style instead of merging" {
	function view(p: Styled): NeonNode {
		return element(<div style={{ width: 1 }} {...p}>hi</div>);
	}
	const root = mounted(view({ style: { height: 2 } }));
	assert mockToString(root) === "<root><div>hi</div></root>", "style is not an attr: " + mockToString(root);
	assert styleOf(root.children[0]) === "height:2px;", "spread style replaces: " + styleOf(root.children[0]);
}

test "an explicit style after a spread replaces the spread's style" {
	function view(p: Styled): NeonNode {
		return element(<div {...p} style={{ width: 1 }}>hi</div>);
	}
	const root = mounted(view({ style: { height: 2 } }));
	assert mockToString(root) === "<root><div>hi</div></root>", "style is not an attr: " + mockToString(root);
	assert styleOf(root.children[0]) === "width:1px;", "explicit style wins: " + styleOf(root.children[0]);
}

interface CardProps {
	title: Accessor<string>;
	body: Accessor<string>;
}

function Card(props: CardProps): NeonNode {
	return element(<div id={props.title()}>{props.body()}</div>);
}

test "a spread onto a component forwards its props and keeps them reactive" {
	const [t, setT] = createSignal("a");
	function view(p: CardProps): NeonNode {
		return element(<Card {...p} />);
	}
	const root = mounted(view({ title: t, body: accessor(() => "b") }));
	assert mockToString(root) === "<root><div id=\"a\">b</div></root>", "component spread initial: " + mockToString(root);
	setT("z");
	flush();
	assert mockToString(root) === "<root><div id=\"z\">b</div></root>", "component spread stays reactive: " + mockToString(root);
}

test "an explicit prop after a spread wins on a component too" {
	function view(p: CardProps): NeonNode {
		return element(<Card {...p} title="late" />);
	}
	const root = mounted(view({ title: accessor(() => "early"), body: accessor(() => "b") }));
	assert mockToString(root) === "<root><div id=\"late\">b</div></root>", "explicit prop overrides the spread: " + mockToString(root);
}

class Badge {
	id: string = "b1";
	title: string = "bt";
}

type AliasedAttrs = Attrs;

interface Holder {
	attrs: Attrs;
	badge: Badge;
	aliased: AliasedAttrs;
}

test "a class-typed value spreads its fields" {
	const b = new Badge();
	const root = mounted(element(<div {...b}>hi</div>));
	assert mockToString(root) === "<root><div id=\"b1\" title=\"bt\">hi</div></root>", "class fields land as attrs: " + mockToString(root);
}

test "an interface-typed field of another type spreads its fields" {
	function view(h: Holder): NeonNode {
		return element(<div {...h.attrs}>hi</div>);
	}
	const h: Holder = { attrs: { id: "x", title: "t" }, badge: new Badge(), aliased: { id: "y", title: null } };
	const root = mounted(view(h));
	assert mockToString(root) === "<root><div id=\"x\" title=\"t\">hi</div></root>", "nested interface field: " + mockToString(root);
}

test "a class-typed field of another type spreads its fields" {
	function view(h: Holder): NeonNode {
		return element(<div {...h.badge}>hi</div>);
	}
	const h: Holder = { attrs: { id: "x", title: "t" }, badge: new Badge(), aliased: { id: "y", title: null } };
	const root = mounted(view(h));
	assert mockToString(root) === "<root><div id=\"b1\" title=\"bt\">hi</div></root>", "nested class field: " + mockToString(root);
}

test "a field whose type is an alias of an interface spreads its fields" {
	function view(h: Holder): NeonNode {
		return element(<div {...h.aliased}>hi</div>);
	}
	const h: Holder = { attrs: { id: "x", title: "t" }, badge: new Badge(), aliased: { id: "y", title: null } };
	const root = mounted(view(h));
	assert mockToString(root) === "<root><div id=\"y\">hi</div></root>", "aliased interface field: " + mockToString(root);
}
