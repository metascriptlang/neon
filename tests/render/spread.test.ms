// `{...props}` on a host tag, decided at compile time from the spread
// expression's TYPE: every field becomes the same channel its explicit twin
// would (attr / dynAttr / evt / style / ref), a later prop beats an earlier one
// while keeping the earlier one's position (setAttribute semantics,
// HOST_ATTR_CONTRACT), null removes, and an Accessor field stays reactive.

import { createSignal, Accessor } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { NeonEvent } from "../../src/render/event";
import { render, mockHost, mockNode, mockToString, fireEvent, HostNode } from "../../src/render/host";

interface Attrs {
	id: string;
	title: string | null;
}

interface Reactive {
	title: Accessor<string>;
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
	assert mockToString(root.children[0]) === "<div title=\"b\">hi</div>", "after set: " + mockToString(root.children[0]);
}
