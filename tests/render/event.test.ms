// The event object a handler receives (src/render/event.ms).
//
// The DOM mapping itself cannot be tested here — it needs a browser — so these
// pin the parts every host shares: the name→type spelling, that the event
// reaches a handler through both emissions, and that a handler which ignores it
// still runs (the compatibility promise that made the arity change affordable).

import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { direct } from "../../src/macros/ui/direct";
import { NeonNode, el, attr, evt, text } from "../../src/render/node";
import { createComponent } from "../../src/render/component";
import { NeonEvent, neonEvent, eventType } from "../../src/render/event";
import { renderToHost, renderNode, mockHost, mockNode, mockToString, fireEvent, fireEventWith, bindText, bindAttr, MockNode, Host, HostNode, NeonView, viewOf } from "../../src/render/host";
import { createTemplate, mountTemplate, childOf, siblingOf } from "../../src/render/template";

test "eventType strips the on prefix and lowercases" {
	assert eventType("onClick") === "click", "onClick → " + eventType("onClick");
	assert eventType("onInput") === "input", "onInput → " + eventType("onInput");
	assert eventType("onMouseDown") === "mousedown", "onMouseDown → " + eventType("onMouseDown");
	assert eventType("click") === "click", "bare name passes through";
	assert eventType("on") === "on", "too short to be a prefix";
}

test "a fresh event carries its type and zero everywhere else" {
	const e = neonEvent("click");
	assert e.type === "click", "type";
	assert e.value === "", "value defaults empty";
	assert e.key === "", "key defaults empty";
	assert e.x === 0, "x defaults 0";
	assert e.y === 0, "y defaults 0";
}

test "a handler on a jsx element receives the event" {
	const host = mockHost();
	const root = mockNode("root");
	let seen = "";
	renderToHost(element(<button onClick={(e: NeonEvent): void => { seen = e.type; }}>go</button>), host, root as unknown as HostNode);

	const btn = root.children[0];
	fireEvent(btn, "onClick");
	assert seen === "click", "handler saw type=" + seen;
}

test "a handler that ignores the event still runs" {
	const host = mockHost();
	const root = mockNode("root");
	let runs = 0;
	renderToHost(element(<button onClick={(): void => { runs = runs + 1; }}>go</button>), host, root as unknown as HostNode);

	fireEvent(root.children[0], "onClick");
	assert runs === 1, "zero-arg handler runs=" + runs.toString();
}

test "an input handler reads the value the host put on the event" {
	const host = mockHost();
	const root = mockNode("root");
	let typed = "";
	renderToHost(element(<input onInput={(e: NeonEvent): void => { typed = e.value; }} />), host, root as unknown as HostNode);

	const e = neonEvent("input");
	e.value = "hello";
	fireEventWith(root.children[0], "onInput", e);
	assert typed === "hello", "handler read value=" + typed;
}

test "a click handler reads the coordinates the host put on the event" {
	const host = mockHost();
	const root = mockNode("root");
	let at = "";
	renderToHost(element(<div onClick={(e: NeonEvent): void => { at = e.x.toString() + "," + e.y.toString(); }} />), host, root as unknown as HostNode);

	const e = neonEvent("click");
	e.x = 12;
	e.y = 34;
	fireEventWith(root.children[0], "onClick", e);
	assert at === "12,34", "handler read at=" + at;
}

test "direct emission delivers the same event as tree emission" {
	const host = mockHost();

	const treeRoot = mockNode("root");
	let treeSaw = "";
	renderToHost(element(<button onClick={(e: NeonEvent): void => { treeSaw = e.type + ":" + e.value; }}>go</button>), host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	let directSaw = "";
	const mount = direct(<button onClick={(e: NeonEvent): void => { directSaw = e.type + ":" + e.value; }}>go</button>);
	host.append(directRoot as unknown as HostNode, mount(host));

	const e = neonEvent("click");
	e.value = "v";
	fireEventWith(treeRoot.children[0], "onClick", e);
	fireEventWith(directRoot.children[0], "onClick", e);
	assert treeSaw === directSaw, "tree=" + treeSaw + " direct=" + directSaw;
	assert treeSaw === "click:v", "both saw " + treeSaw;
}

test "a handler drives a signal through the event value" {
	const host = mockHost();
	const root = mockNode("root");
	const [name, setName] = createSignal("");
	renderToHost(element(<input onInput={(e: NeonEvent): void => { setName(e.value); }} />), host, root as unknown as HostNode);

	const e = neonEvent("input");
	e.value = "son";
	fireEventWith(root.children[0], "onInput", e);
	assert name() === "son", "signal now " + name();
}
