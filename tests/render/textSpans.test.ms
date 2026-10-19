import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { MockNode, mockNode, mockHost, render, mockToString, HostNode } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { Text } from "../../src/components/primitives";
import { Host, TextSpan } from "../../src/render/hostTypes";
import { NeonEvent, neonEvent } from "../../src/render/event";

const RED: Style = { color: "#ff0000" };
const BLUE: Style = { color: "#0000ff" };

test "on a host without setSpans, spans lay out as nested Texts in order" {
	const root: MockNode = mockNode("root");
	render(element(<Text spans={[{ text: "error", style: RED }, { text: ": not found" }]} />), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><text><text>error</text><text>: not found</text></text></root>", mockToString(root);
	const text = root.children[0];
	assert text.children[0].style === RED, "the first span carries its style";
	assert text.children[1].style === null, "a span with no style sets none";
}

test "a spans change keeps each span's nodes by position, and grows and shrinks at the end" {
	const root: MockNode = mockNode("root");
	const [spans, setSpans] = createSignal<TextSpan[]>([{ text: "a", style: RED }, { text: "b" }]);
	render(element(<Text spans={spans()} />), mockHost(), root as unknown as HostNode);
	const text = root.children[0];
	const first = text.children[0];
	setSpans([{ text: "A", style: BLUE }, { text: "B" }, { text: "C", style: RED }]);
	assert mockToString(root) === "<root><text><text>A</text><text>B</text><text>C</text></text></root>", mockToString(root);
	assert text.children[0] === first, "the first span kept its node";
	assert first.style === BLUE, "and took the new style";
	setSpans([{ text: "x" }]);
	assert mockToString(root) === "<root><text><text>x</text></text></root>", mockToString(root);
	assert text.children[0] === first, "the first span still kept its node";
}

test "a Text takes spans or children, not both" {
	let message = "";
	try {
		render(element(<Text spans={[{ text: "a" }]}>b</Text>), mockHost(), mockNode("root") as unknown as HostNode);
	} catch (e) { message = e.message; }
	assert message.indexOf("spans or children") >= 0, message;
}

test "on a host without setSpans, a span's onPress is its nested Text's press, and follows a new handler" {
	const root: MockNode = mockNode("root");
	let log = "";
	const [spans, setSpans] = createSignal<TextSpan[]>([{ text: "a" }, { text: "b", onPress: (e: NeonEvent): void => { log += "first;"; } }]);
	render(element(<Text spans={spans()} />), mockHost(), root as unknown as HostNode);
	const second = root.children[0].children[1];
	second.events[0].handler(neonEvent("press"));
	setSpans([{ text: "a" }, { text: "b", onPress: (e: NeonEvent): void => { log += "second;"; } }]);
	second.events[0].handler(neonEvent("press"));
	setSpans([{ text: "a" }, { text: "b" }]);
	second.events[0].handler(neonEvent("press"));
	assert log === "first;second;", log;
}

test "a host with setSpans but no paragraph capability refuses a Text instead of laying it out as nodes" {
	const host: Host = { ...mockHost(), setSpans: (node: HostNode, spans: TextSpan[]): void => {} };
	let message = "";
	try {
		render(element(<Text>a</Text>), host, mockNode("root") as unknown as HostNode);
	} catch (e) { message = e.message; }
	assert message.indexOf("paragraph capability") >= 0, message;
}
