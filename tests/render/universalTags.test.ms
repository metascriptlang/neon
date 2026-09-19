// The universal tag vocabulary (user decision 2026-09-03): users write
// View/Text/TextInput/Pressable — div/span are HTML-isms each HOST translates
// in its own createElement. These pin: the wire-tag table (htmlTagFor, shared
// by SSR and the browser host), the starter components rendering the lowercase
// wire tags (mock records them as written), the vocabulary working end to end
// through the event surface, and the terminal's box translation.

import { element } from "../../src/macros/ui/element";
import { View, Text, TextInput, Pressable } from "../../src/components/primitives";
import { neonEvent } from "../../src/render/event";
import { htmlTagFor } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { HostNode, MockNode, mockHost, mockNode, render, fireEvent, fireEventWith, mockToString } from "../../src/render/host";
import { terminalHost } from "../../src/platform/terminal/host";
import { TerminalNode } from "../../src/platform/terminal/types";

test "htmlTagFor maps the wire vocabulary, unknown tags pass through" {
	assert htmlTagFor("view") === "div", "view";
	assert htmlTagFor("text") === "span", "text";
	assert htmlTagFor("textinput") === "input", "textinput";
	assert htmlTagFor("pressable") === "button", "pressable";
	assert htmlTagFor("div") === "div", "raw html still passes";
	assert htmlTagFor("MyThing") === "MyThing", "custom tags pass through";
}

test "the components render the wire tags the mock records" {
	const host = mockHost();
	const root = mockNode("root");
	render(element(<View><Text>hi</Text></View>), host, root as unknown as HostNode);
	const s = mockToString(root as unknown as MockNode);
	assert s.indexOf("view") >= 0, "mock kept view: " + s;
	assert s.indexOf("text") >= 0, "mock kept text: " + s;
}

test "Pressable speaks onPress end to end on the mock" {
	const host = mockHost();
	const root = mockNode("root");
	let presses = 0;
	render(element(<Pressable onPress={(): void => { presses = presses + 1; }}>go</Pressable>), host, root as unknown as HostNode);
	fireEvent(root.children[0], "onPress");
	fireEvent(root.children[0], "onPress");
	assert presses === 2, "presses=" + presses.toString();
}

test "TextInput hands onChangeText the text in the universal vocabulary" {
	const host = mockHost();
	const root = mockNode("root");
	let typed = "";
	render(element(<TextInput onChangeText={(t: string): void => { typed = t; }} />), host, root as unknown as HostNode);
	const e = neonEvent("changetext");
	e.value = "chao";
	fireEventWith(root.children[0], "onChangeText", e);
	assert typed === "chao", "typed=" + typed;
}

test "ssr serializes the vocabulary as html" {
	const s = renderToString(element(<View><Text>hi</Text></View>));
	assert s === "<div><span>hi</span></div>", "ssr wrote " + s;
}

test "the terminal host maps the vocabulary onto its boxes" {
	const host = terminalHost();
	const v = host.createElement("view") as unknown as TerminalNode;
	const p = host.createElement("pressable") as unknown as TerminalNode;
	const hr = host.createElement("hr") as unknown as TerminalNode;
	assert v.tag === "box", "view→" + v.tag;
	assert p.tag === "box", "pressable→" + p.tag;
	assert hr.tag === "hr", "native terminal tags pass: " + hr.tag;
}
