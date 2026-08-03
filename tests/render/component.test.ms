// Capitalized JSX tags — element() emits createComponent(Tag, props). V1 contract:
// expression props arrive as thunks, string literals as strings, children structural.

import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { el, attr, text, dynText, NeonNode, renderToString } from "../../src/render/node";
import { createComponent } from "../../src/render/component";
import { renderToHost, mockHost, mockNode, mockToString, HostNode } from "../../src/render/host";

interface CounterProps {
	count: () => number;
	label: string;
}

let counterRuns = 0;

function Counter(props: CounterProps): NeonNode {
	counterRuns = counterRuns + 1;
	return element(<p class={props.label}>n={props.count().toString()}</p>);
}

test "capitalized tag defers and renders through createComponent" {
	counterRuns = 0;
	const [n, setN] = createSignal(1);
	const view = element(<Counter count={n()} label="c" />);
	assert counterRuns === 0, "body must not run at tree construction";
	const host = mockHost();
	const root = mockNode("root");
	renderToHost(view, host, root as unknown as HostNode);
	assert mockToString(root) === "<root><p class=\"c\">n=1</p></root>", "initial: " + mockToString(root);
	setN(5);
	assert mockToString(root) === "<root><p class=\"c\">n=5</p></root>", "after set: " + mockToString(root);
	assert counterRuns === 1, "prop change must not re-run the body";
}

test "component nests inside a lowercase tree" {
	const [n, setN] = createSignal(2);
	const view = element(<div><Counter count={n()} label="x" /></div>);
	const out = renderToString(view);
	assert out === "<div><p class=\"x\">n=2</p></div>", "got " + out;
}

interface CardProps {
	title: string;
	children: NeonNode;
}

function Card(props: CardProps): NeonNode {
	return el("section", [attr("title", props.title)], [], [props.children]);
}

test "single element child passes as the children prop" {
	const view = element(<Card title="t"><p>inner</p></Card>);
	const out = renderToString(view);
	assert out === "<section title=\"t\"><p>inner</p></section>", "got " + out;
}

interface WrapProps {
	children: NeonNode[];
}

function Wrap(props: WrapProps): NeonNode {
	return el("ul", [], [], props.children);
}

test "several children arrive as an array" {
	const view = element(<Wrap><li>a</li><li>b</li></Wrap>);
	const out = renderToString(view);
	assert out === "<ul><li>a</li><li>b</li></ul>", "got " + out;
}
