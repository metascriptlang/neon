// Capitalized JSX tags — element() emits createComponent(Tag, props). V1 contract:
// expression props arrive as thunks, string literals as strings, children structural.

import { createSignal, accessor, Accessor } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { element } from "../../src/macros/ui/element";
import { el, attr, text, dynText, NeonNode } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { createComponent } from "../../src/render/component";
import { render, mockHost, mockNode, mockToString, HostNode } from "../../src/render/host";
import { Show, For } from "../../src/macros/ui/flow";

interface CounterProps {
	count: Accessor<number>;
	label: Accessor<string>;
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
	render(view, host, root as unknown as HostNode);
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
	title: Accessor<string>;
	children: NeonNode;
}

function Card(props: CardProps): NeonNode {
	return <section title={props.title()}>{props.children}</section>;
}

test "single element child passes as the children prop" {
	const view = element(<Card title="t"><p>inner</p></Card>);
	const out = renderToString(view);
	assert out === "<section title=\"t\"><p>inner</p></section>", "got " + out;
}

interface WrapProps {
	children: NeonNode;
}

function Wrap(props: WrapProps): NeonNode {
	return element(<ul>{props.children}</ul>);
}

test "one element child arrives as one NeonNode" {
	const out = renderToString(element(<Wrap><li>a</li></Wrap>));
	assert out === "<ul><li>a</li></ul>", "got " + out;
}

test "several children arrive as one NeonNode that places every root" {
	const out = renderToString(element(<Wrap><li>a</li><li>b</li></Wrap>));
	assert out === "<ul><li>a</li><li>b</li></ul>", "got " + out;
}

test "one text child arrives as one NeonNode" {
	const out = renderToString(element(<Wrap>plain</Wrap>));
	assert out === "<ul>plain</ul>", "got " + out;
}

test "text beside an element keeps source order inside the one NeonNode" {
	const out = renderToString(element(<Wrap>lead<li>a</li>tail</Wrap>));
	assert out === "<ul>lead<li>a</li>tail</ul>", "got " + out;
}

test "a NeonNode value as the only child crosses as itself" {
	const item: NeonNode = element(<li>held</li>);
	const out = renderToString(element(<Wrap>{item}</Wrap>));
	assert out === "<ul><li>held</li></ul>", "got " + out;
}

test "a For call as the only child mounts its rows" {
	const [items, setItems] = createSignal<number[]>([1, 2]);
	const host = mockHost();
	const root = mockNode("root");
	render(element(<Wrap>{For<number>({ each: () => items(), children: (n, i) => element(<li>{n.toString()}</li>) })}</Wrap>), host, root as unknown as HostNode);
	assert mockToString(root) === "<root><ul><li>1</li><li>2</li></ul></root>", "initial: " + mockToString(root);
	setItems([2, 3, 1]);
	assert mockToString(root) === "<root><ul><li>2</li><li>3</li><li>1</li></ul></root>", "after set: " + mockToString(root);
}

test "a <For> tag as the only child mounts its rows" {
	const [items, setItems] = createSignal<number[]>([1, 2]);
	const host = mockHost();
	const root = mockNode("root");
	render(element(<Wrap><For each={items()}>{(n: number, i: Accessor<number>): NeonNode => element(<li>{n.toString()}</li>)}</For></Wrap>), host, root as unknown as HostNode);
	assert mockToString(root) === "<root><ul><li>1</li><li>2</li></ul></root>", "initial: " + mockToString(root);
	setItems([3]);
	assert mockToString(root) === "<root><ul><li>3</li></ul></root>", "after set: " + mockToString(root);
}

test "a reactive text child surrounded by whitespace stays live" {
	const [word, setWord] = createSignal("v");
	const host = mockHost();
	const root = mockNode("root");
	render(element(<Wrap>
		{word()}
	</Wrap>), host, root as unknown as HostNode);
	assert mockToString(root) === "<root><ul>v</ul></root>", "initial: " + mockToString(root);
	setWord("w");
	assert mockToString(root) === "<root><ul>w</ul></root>", "after set: " + mockToString(root);
}

test "a reactive text child surrounded by whitespace stays live under a host tag" {
	const [word, setWord] = createSignal("v");
	const host = mockHost();
	const root = mockNode("root");
	render(element(<div><Wrap>
		{word()}
	</Wrap></div>), host, root as unknown as HostNode);
	assert mockToString(root) === "<root><div><ul>v</ul></div></root>", "initial: " + mockToString(root);
	setWord("w");
	assert mockToString(root) === "<root><div><ul>w</ul></div></root>", "after set: " + mockToString(root);
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
	render(view, host, root as unknown as HostNode);
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
	render(view, host, root as unknown as HostNode);
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
	render(view, host, root as unknown as HostNode);
	assert leakRuns === 0, "no cleanup while mounted";
	setOn(false);
	assert leakRuns === 1, "cleanup fires when Show drops the component, got " + leakRuns.toString();
}

let bareRuns = 0;

function Bare(props: CounterProps): NeonNode {
	bareRuns = bareRuns + 1;
	return element(<p class={props.label}>n={props.count.toString()}</p>);
}

test "a bare accessor prop read is the value and stays reactive" {
	bareRuns = 0;
	const [n, setN] = createSignal<number>(1);
	const view = element(<Bare count={n()} label="b" />);
	const host = mockHost();
	const root = mockNode("root");
	render(view, host, root as unknown as HostNode);
	assert mockToString(root) === "<root><p class=\"b\">n=1</p></root>", "initial: " + mockToString(root);
	setN(4);
	assert mockToString(root) === "<root><p class=\"b\">n=4</p></root>", "after set: " + mockToString(root);
	assert bareRuns === 1, "body runs once, got " + bareRuns.toString();
}

function Destr({ label, count }: CounterProps): NeonNode {
	return element(<p class={label}>n={count.toString()}</p>);
}

test "a destructured props parameter reads bare and stays reactive" {
	const [n, setN] = createSignal<number>(2);
	const view = element(<Destr count={n()} label="d" />);
	const host = mockHost();
	const root = mockNode("root");
	render(view, host, root as unknown as HostNode);
	assert mockToString(root) === "<root><p class=\"d\">n=2</p></root>", "initial: " + mockToString(root);
	setN(7);
	assert mockToString(root) === "<root><p class=\"d\">n=7</p></root>", "after set: " + mockToString(root);
}

interface StyledProps {
	style: Accessor<{ gap: number }>;
	label: Accessor<string>;
}

function Styled(props: StyledProps): NeonNode {
	return element(<p class={props.label}>{props.style.gap.toString()}</p>);
}

test "an object literal prop is stamped by the accessor's declared payload" {
	const view = element(<Styled style={{ gap: 12 }} label="s" />);
	assert renderToString(view) === "<p class=\"s\">12</p>", "got " + renderToString(view);
}
