// `{...props}` on a host tag, decided at compile time from the spread
// expression's TYPE: every field becomes the same channel its explicit twin
// would (attr / dynAttr / evt / style / ref), a later prop beats an earlier one
// while keeping the earlier one's position (setAttribute semantics,
// HOST_ATTR_CONTRACT), null removes, and an Accessor field stays reactive.

import { createSignal, Accessor, accessor } from "../../src/core/signal";
import { NeonNode, renderToString } from "../../src/render/node";
import { Style } from "../../src/render/style";
import { element } from "../../src/macros/ui/element";
import { direct } from "../../src/macros/ui/direct";
import { Show } from "../../src/macros/ui/flow";
import { NeonEvent } from "../../src/render/event";
import { renderToHost, mockHost, mockNode, mockToString, fireEvent, HostNode, NeonView } from "../../src/render/host";

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

interface Styled {
	style: Style;
}

test "an object literal spread contributes one attr per field" {
	const p = { id: "x", title: "t" };
	const n: NeonNode = element(<div {...p}>hi</div>);
	assert renderToString(n) === "<div id=\"x\" title=\"t\">hi</div>", "both fields land as attrs";
}

test "a spread inside a container element expands the same way" {
	const p = { id: "x" };
	const flag = true;
	const n: NeonNode = element(<div>{flag ? <span {...p}>hi</span> : null}</div>);
	const host = mockHost();
	const root = mockNode("root");
	renderToHost(n, host, root as unknown as HostNode);
	assert mockToString(root.children[0]) === "<div><span id=\"x\">hi</span></div>", "nested spread expands";
}

test "an explicit attr after a spread wins and keeps the spread's position" {
	const p = { id: "x", title: "t" };
	const n: NeonNode = element(<div {...p} id="late">hi</div>);
	assert renderToString(n) === "<div id=\"late\" title=\"t\">hi</div>", "later explicit attr wins in place";
}

test "a spread after an explicit attr wins" {
	const p = { id: "x" };
	const n: NeonNode = element(<div id="early" class="c" {...p}>hi</div>);
	assert renderToString(n) === "<div id=\"x\" class=\"c\">hi</div>", "later spread wins in place";
}

test "the later of two spreads wins" {
	const a = { id: "a", title: "ta" };
	const b = { id: "b" };
	const n: NeonNode = element(<div {...a} {...b}>hi</div>);
	assert renderToString(n) === "<div id=\"b\" title=\"ta\">hi</div>", "second spread overrides the first";
}

test "a null field removes the attribute" {
	function view(p: Attrs): NeonNode {
		return element(<div {...p}>hi</div>);
	}
	assert renderToString(view({ id: "x", title: null })) === "<div id=\"x\">hi</div>", "null field is absent";
	assert renderToString(view({ id: "x", title: "t" })) === "<div id=\"x\" title=\"t\">hi</div>", "set field is present";
}

test "a null field removes an attribute already written by an earlier prop" {
	function view(p: Attrs): NeonNode {
		return element(<div title="early" {...p}>hi</div>);
	}
	const host = mockHost();
	const root = mockNode("root");
	renderToHost(view({ id: "x", title: null }), host, root as unknown as HostNode);
	assert mockToString(root.children[0]) === "<div id=\"x\">hi</div>", "null erases the earlier title";
}

test "an Accessor field stays reactive" {
	const [t, setT] = createSignal("a");
	function view(p: Reactive): NeonNode {
		return element(<div {...p}>hi</div>);
	}
	const n = view({ title: t });
	assert renderToString(n) === "<div title=\"a\">hi</div>", "initial accessor read";
	setT("b");
	assert renderToString(n) === "<div title=\"b\">hi</div>", "accessor tracks the signal";
}

test "an on* field becomes an event" {
	let hits = 0;
	function view(p: Handlers): NeonNode {
		return element(<div {...p}>hi</div>);
	}
	const host = mockHost();
	const root = mockNode("root");
	renderToHost(view({ onPress: (e: NeonEvent) => { hits = hits + 1; } }), host, root as unknown as HostNode);
	fireEvent(root.children[0], "onPress");
	assert hits === 1, "spread handler fired";
}

test "a style field replaces an earlier style instead of merging" {
	function view(p: Styled): NeonNode {
		return element(<div style={{ width: 1 }} {...p}>hi</div>);
	}
	assert renderToString(view({ style: { height: 2 } })) === "<div style=\"height:2px;\">hi</div>", "spread style replaces";
}

test "an explicit style after a spread replaces the spread's style" {
	function view(p: Styled): NeonNode {
		return element(<div {...p} style={{ width: 1 }}>hi</div>);
	}
	assert renderToString(view({ style: { height: 2 } })) === "<div style=\"width:1px;\">hi</div>", "explicit style wins";
}

// Direct emission (NeonView): the same classification, the same override order.

test "direct emission expands a spread into the same attrs" {
	const p = { id: "x", title: "t" };
	const host = mockHost();
	const root = mockNode("root");
	const m = direct(<div {...p}>hi</div>);
	m(host, root as unknown as HostNode, null);
	assert mockToString(root.children[0]) === "<div id=\"x\" title=\"t\">hi</div>", "direct spread attrs";
}

test "direct emission gives a later prop the win in place" {
	const p = { id: "x", title: "t" };
	const host = mockHost();
	const root = mockNode("root");
	const m = direct(<div title="early" {...p} id="late">hi</div>);
	m(host, root as unknown as HostNode, null);
	assert mockToString(root.children[0]) === "<div title=\"t\" id=\"late\">hi</div>", "direct override order";
}

test "direct emission removes a null field" {
	function view(p: Attrs): NeonView {
		return direct(<div title="early" {...p}>hi</div>);
	}
	const host = mockHost();
	const root = mockNode("root");
	view({ id: "x", title: null })(host, root as unknown as HostNode, null);
	assert mockToString(root.children[0]) === "<div id=\"x\">hi</div>", "direct null removes";
}

test "direct emission keeps an Accessor field reactive" {
	const [t, setT] = createSignal("a");
	function view(p: Reactive): NeonView {
		return direct(<div {...p}>hi</div>);
	}
	const host = mockHost();
	const root = mockNode("root");
	view({ title: t })(host, root as unknown as HostNode, null);
	assert mockToString(root.children[0]) === "<div title=\"a\">hi</div>", "direct accessor initial";
	setT("b");
	assert mockToString(root.children[0]) === "<div title=\"b\">hi</div>", "direct accessor updates";
}

test "direct emission routes an on* field to addEvent" {
	let hits = 0;
	function view(p: Handlers): NeonView {
		return direct(<div {...p}>hi</div>);
	}
	const host = mockHost();
	const root = mockNode("root");
	view({ onPress: (e: NeonEvent) => { hits = hits + 1; } })(host, root as unknown as HostNode, null);
	fireEvent(root.children[0], "onPress");
	assert hits === 1, "direct spread handler fired";
}

test "direct emission lets a spread style replace an earlier one" {
	function view(p: Styled): NeonView {
		return direct(<div style={{ width: 1 }} {...p}>hi</div>);
	}
	const host = mockHost();
	const root = mockNode("root");
	view({ style: { height: 2 } })(host, root as unknown as HostNode, null);
	const st = root.children[0].style;
	assert st !== null && (st as Style).height === 2 && (st as Style).width === null, "direct spread style replaces";
}

// A capitalized tag takes the same expansion, then the V1 prop contract wraps
// each value in accessor() unless it already is one.

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
	const n = view({ title: t, body: accessor(() => "b") });
	assert renderToString(n) === "<div id=\"a\">b</div>", "component spread initial";
	setT("z");
	assert renderToString(n) === "<div id=\"z\">b</div>", "component spread stays reactive";
}

test "an explicit prop after a spread wins on a component too" {
	function view(p: CardProps): NeonNode {
		return element(<Card {...p} title="late" />);
	}
	const n = view({ title: accessor(() => "early"), body: accessor(() => "b") });
	assert renderToString(n) === "<div id=\"late\">b</div>", "explicit prop overrides the spread";
}
