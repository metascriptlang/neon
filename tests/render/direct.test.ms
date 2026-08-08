// Direct emission V1 — differential against tree emission on the mock host:
// same JSX through both emissions must be byte-identical, before and after
// signal updates (tree emission is the oracle — docs/RENDER-MODEL.md).

import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { onCleanup } from "../../src/core/cleanup";
import { element } from "../../src/macros/ui/element";
import { direct } from "../../src/macros/ui/direct";
import { NeonNode, el, attr } from "../../src/render/node";
import { createComponent } from "../../src/render/component";
import { Show, For } from "../../src/macros/ui/flow";
import { renderToHost, renderNode, mockHost, mockNode, mockToString, fireEvent, MockNode, Host, HostNode } from "../../src/render/host";

test "static + dynamic text + event: direct matches tree" {
	const [name, setName] = createSignal("an");
	let clicks = 0;
	const inc = () => { clicks = clicks + 1; };
	const host = mockHost();

	const treeRoot = mockNode("root");
	const view: NeonNode = element(<div class="box"><p>hello {name()}</p><button onClick={inc}>+</button></div>);
	renderToHost(view, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div class="box"><p>hello {name()}</p><button onClick={inc}>+</button></div>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setName("binh");
	assert mockToString(treeRoot) === mockToString(directRoot), "after set: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);

	const btn = (directRoot as MockNode).children[0].children[1];
	fireEvent(btn, "onClick");
	assert clicks === 1, "clicks=" + clicks.toString();
}

test "deep nesting: direct matches tree" {
	const [v, setV] = createSignal("x");
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<ul><li><span>a</span></li><li>{v()}</li></ul>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<ul><li><span>a</span></li><li>{v()}</li></ul>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: " + mockToString(directRoot);
	setV("y");
	assert mockToString(treeRoot) === mockToString(directRoot), "after set: " + mockToString(directRoot);
}

test "multiple attrs and multiple dynamic spots keep distinct temps" {
	const [a, setA] = createSignal("1");
	const [b, setB] = createSignal("2");
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div id="x" class="y"><p>{a()}</p><p>{b()}</p><span>{a()}</span></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div id="x" class="y"><p>{a()}</p><p>{b()}</p><span>{a()}</span></div>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setA("7");
	assert mockToString(treeRoot) === mockToString(directRoot), "after setA: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setB("9");
	assert mockToString(treeRoot) === mockToString(directRoot), "after setB: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot).includes("7") && mockToString(directRoot).includes("9"), "both updated: " + mockToString(directRoot);
}

// ---- D1: component tags + Show through direct emission (tree side = oracle) ----

interface GaugeProps {
	count: () => number;
	label: string;
}

let gaugeRuns = 0;

function Gauge(props: GaugeProps): NeonNode {
	gaugeRuns = gaugeRuns + 1;
	return element(<p class={props.label}>n={props.count().toString()}</p>);
}

let leakRuns = 0;

function Leak(props: GaugeProps): NeonNode {
	onCleanup(() => { leakRuns = leakRuns + 1; });
	return element(<i>{props.count().toString()}</i>);
}

interface CardProps {
	title: string;
	children: NeonNode;
}

function Card(props: CardProps): NeonNode {
	return el("section", [attr("title", props.title)], [], [props.children]);
}

function applyFn(f: () => number): number { return f(); }

test "component child: defer, bodyRuns once, reactive prop updates match tree" {
	gaugeRuns = 0;
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div><Gauge count={n()} label="g" /></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div><Gauge count={n()} label="g" /></div>);
	assert gaugeRuns === 1, "direct() must not run the body before mount, got " + gaugeRuns.toString();
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);
	assert gaugeRuns === 2, "one body run per emission after mount, got " + gaugeRuns.toString();

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setN(5);
	assert mockToString(treeRoot) === mockToString(directRoot), "after set: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setN(9);
	assert mockToString(treeRoot) === mockToString(directRoot), "after 2nd set: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert gaugeRuns === 2, "sets must not re-run bodies, got " + gaugeRuns.toString();
}

test "root-position component: deferred until mount, matches tree" {
	gaugeRuns = 0;
	const [n, setN] = createSignal<number>(3);
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<Gauge count={n()} label="r" />);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<Gauge count={n()} label="r" />);
	assert gaugeRuns === 1, "root component body deferred until mount, got " + gaugeRuns.toString();
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);
	assert gaugeRuns === 2, "body ran once at mount, got " + gaugeRuns.toString();

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setN(4);
	assert mockToString(treeRoot) === mockToString(directRoot), "after set: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
}

test "prop expression with a nested arrow capturing outer variables stays reactive" {
	const base: number = 100;
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div><Gauge count={applyFn(() => n() + base)} label="a" /></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div><Gauge count={applyFn(() => n() + base)} label="a" /></div>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setN(2);
	assert mockToString(treeRoot) === mockToString(directRoot), "after set: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
}

test "Show flip through direct: cleanup fires, span matches tree on both flips" {
	leakRuns = 0;
	const [n, setN] = createSignal<number>(1);
	const [on, setOn] = createSignal(true);
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div><Show when={on()}><Leak count={n()} label="l" /></Show></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div><Show when={on()}><Leak count={n()} label="l" /></Show></div>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert leakRuns === 0, "no cleanup while mounted";
	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	const dDiv = (directRoot as MockNode).children[0];
	assert dDiv.children.length === 2, "region span (child + anchor) under direct div, got " + dDiv.children.length.toString();
	setOn(false);
	assert leakRuns === 2, "one cleanup per emission on flip, got " + leakRuns.toString();
	assert mockToString(treeRoot) === mockToString(directRoot), "after flip: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setOn(true);
	assert mockToString(treeRoot) === mockToString(directRoot), "after flip back: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setN(7);
	assert mockToString(treeRoot) === mockToString(directRoot), "rebuilt child reactive: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
}

test "single element child passes as the children prop through direct" {
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div><Card title="t"><p>inner</p></Card></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div><Card title="t"><p>inner</p></Card></div>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
}

test "For reorder through direct matches tree" {
	const [items, setItems] = createSignal<number[]>([1, 2, 3]);
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<ul><For each={items()}>{(item: number, i: () => number): NeonNode => element(<li>{item.toString()}</li>)}</For></ul>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<ul><For each={items()}>{(item: number, i: () => number): NeonNode => element(<li>{item.toString()}</li>)}</For></ul>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setItems([3, 1, 2]);
	assert mockToString(treeRoot) === mockToString(directRoot), "after reorder: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setItems([3, 1, 2, 4]);
	assert mockToString(treeRoot) === mockToString(directRoot), "after append: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setItems([2]);
	assert mockToString(treeRoot) === mockToString(directRoot), "after shrink: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
}
