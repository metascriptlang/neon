// Capitalized JSX tags — element() emits createComponent(Tag, props). V1 contract:
// expression props arrive as thunks, string literals as strings, children structural.

import { createSignal } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { element } from "../../src/macros/ui/element";
import { el, attr, text, dynText, NeonNode, renderToString } from "../../src/render/node";
import { createComponent } from "../../src/render/component";
import { renderToHost, mockHost, mockNode, mockToString, HostNode } from "../../src/render/host";
import { Show } from "../../src/macros/ui/flow";

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

let gaugeRuns = 0;

function Gauge(props: CounterProps): NeonNode {
	gaugeRuns = gaugeRuns + 1;
	return element(<p class={props.label}>n={props.count().toString()}</p>);
}

test "reactive prop E2E: dynText updates across sets, body runs once" {
	gaugeRuns = 0;
	const [n, setN] = createSignal<number>(1);
	const view = element(<Gauge count={n()} label="g" />);
	const host = mockHost();
	const root = mockNode("root");
	renderToHost(view, host, root as unknown as HostNode);
	assert gaugeRuns === 1, "mounted once, got " + gaugeRuns.toString();
	assert mockToString(root) === "<root><p class=\"g\">n=1</p></root>", "initial: " + mockToString(root);
	setN(3);
	assert mockToString(root) === "<root><p class=\"g\">n=3</p></root>", "after first set: " + mockToString(root);
	setN(9);
	assert mockToString(root) === "<root><p class=\"g\">n=9</p></root>", "after second set: " + mockToString(root);
	assert gaugeRuns === 1, "two sets must not re-run the body, got " + gaugeRuns.toString();
}

function applyFn(f: () => number): number { return f(); }

test "prop expression with a nested arrow capturing outer variables stays reactive" {
	const base: number = 100;
	const [n, setN] = createSignal<number>(1);
	const view = element(<Gauge count={applyFn(() => n() + base)} label="a" />);
	const host = mockHost();
	const root = mockNode("root");
	renderToHost(view, host, root as unknown as HostNode);
	assert mockToString(root) === "<root><p class=\"a\">n=101</p></root>", "initial: " + mockToString(root);
	setN(2);
	assert mockToString(root) === "<root><p class=\"a\">n=102</p></root>", "after set: " + mockToString(root);
}

let leakRuns = 0;

function Leak(props: CounterProps): NeonNode {
	onCleanup(() => { leakRuns = leakRuns + 1; });
	return element(<i>{props.count().toString()}</i>);
}

test "unmounting a Show region through JSX fires the component's onCleanup" {
	leakRuns = 0;
	const [n, setN] = createSignal<number>(1);
	const [on, setOn] = createSignal(true);
	const view = element(<div><Show when={on()}><Leak count={n()} label="l" /></Show></div>);
	const host = mockHost();
	const root = mockNode("root");
	renderToHost(view, host, root as unknown as HostNode);
	assert leakRuns === 0, "no cleanup while mounted";
	setOn(false);
	assert leakRuns === 1, "cleanup fires when Show drops the component, got " + leakRuns.toString();
}
