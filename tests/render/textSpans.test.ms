import { Accessor, createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { MockNode, mockNode, mockHost, render, mockToString, HostNode } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { Text, View } from "../../src/components/primitives";
import { Host, NeonNode, TextSpan } from "../../src/render/hostTypes";
import { spanParagraph } from "../../src/render/spanHost";
import { setTextContent } from "../../src/render/paragraph";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { flush } from "../../src/core/runtime";
import { createRenderEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { text } from "../../src/render/node";
import { Errored } from "../../src/macros/ui/flow";

const RED: Style = { color: "#ff0000" };
const BLUE: Style = { color: "#0000ff" };

test "on a host without a paragraph capability, spans lay out as nested Texts in order" {
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
	flush();
	assert mockToString(root) === "<root><text><text>A</text><text>B</text><text>C</text></text></root>", mockToString(root);
	assert text.children[0] === first, "the first span kept its node";
	assert first.style === BLUE, "and took the new style";
	setSpans([{ text: "x" }]);
	flush();
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

test "on a host without a paragraph capability, a span's onPress is its nested Text's press, and follows a new handler" {
	const root: MockNode = mockNode("root");
	let log = "";
	const [spans, setSpans] = createSignal<TextSpan[]>([{ text: "a" }, { text: "b", onPress: (e: NeonEvent): void => { log += "first;"; } }]);
	render(element(<Text spans={spans()} />), mockHost(), root as unknown as HostNode);
	const second = root.children[0].children[1];
	second.events[0].handler(neonEvent("press"));
	setSpans([{ text: "a" }, { text: "b", onPress: (e: NeonEvent): void => { log += "second;"; } }]);
	flush();
	second.events[0].handler(neonEvent("press"));
	setSpans([{ text: "a" }, { text: "b" }]);
	flush();
	second.events[0].handler(neonEvent("press"));
	assert log === "first;second;", log;
}

test "a label built by hand reaches a paragraph host as one span, and no node goes into it" {
	let got = "";
	const deliver = (node: HostNode, spans: TextSpan[]): void => {
		for (const s of spans) { got += "[" + s.text + "]"; }
	};
	const host: Host = { ...mockHost(), paragraph: (h: Host, node: HostNode, before: HostNode | null, kids: NeonNode | null, spans: Accessor<TextSpan[]> | null): void => {
		spanParagraph(deliver, node, kids, spans);
	} };
	const label: MockNode = mockNode("text");
	setTextContent(host, label as unknown as HostNode, "did not mount");
	assert got === "[did not mount]", got;
	assert label.children.length === 0, mockToString(label);
}

function paragraphHost(log: string[]): Host {
	return { ...mockHost(), paragraph: (h: Host, node: HostNode, before: HostNode | null, kids: NeonNode | null, spans: Accessor<TextSpan[]> | null): void => {
		spanParagraph((n: HostNode, got: TextSpan[]): void => {
			let line = "";
			for (const s of got) { line += "[" + s.text + "]"; }
			log.push(line);
		}, node, kids, spans);
	} };
}

test "an Errored inside a Text parks its content off the paragraph behind the fallback, and a reset brings the same content back" {
	const [a, setA] = createSignal(0);
	const bodyRuns = [0];
	let again: (() => void) | null = null;
	const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		bodyRuns[0] = bodyRuns[0] + 1;
		createRenderEffect<number>(
			(p: number | null): number => a(),
			(v: number, p: number | null): Cleanup | null => { if (v === 1) { throw new Error("late"); } return null; },
		);
		text("ok")(host, parent, before);
	};
	const fallback = (err: Accessor<Error>, reset: () => void): NeonNode => { again = reset; return text("caught"); };
	const log: string[] = [];
	const dispose = render(element(<Text>{text("a")}{Errored({ children: content, fallback })}{text("b")}</Text>), paragraphHost(log), mockNode("root") as unknown as HostNode);
	const last = (): string => log[log.length - 1];
	assert last() === "[a][ok][b]", "mounted: " + last();
	setA(1);
	flush();
	assert last() === "[a][caught][b]", "failed: " + last();
	setA(0);
	flush();
	(again as () => void)();
	flush();
	assert last() === "[a][ok][b]", "reset: " + last();
	assert bodyRuns[0] === 1, "the content ran once: " + bodyRuns[0].toString();
	dispose();
}

test "a View inside a Text on a paragraph host is still refused by name" {
	let message = "";
	try {
		render(element(<Text>a <View style={{ width: 4, height: 4 }} /></Text>), paragraphHost([]), mockNode("root") as unknown as HostNode);
	} catch (e) { message = e.message; }
	assert message.indexOf("<view> inside a Text is an inline view") >= 0, message;
}
