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
import { renderToHost, renderNode, mockHost, mockNode, mockToString, fireEvent, bindText, bindAttr, MockNode, Host, HostNode } from "../../src/render/host";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createTemplate, mountTemplate, childOf, siblingOf } from "../../src/render/template";

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

// ---- D2: attr classification + typed style through direct emission ----

const dsheet = createStyles({
	box: { width: 40, height: 10 },
});

test "reactive attr through direct matches tree" {
	const [cls, setCls] = createSignal("red");
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<p class={cls()}>x</p>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<p class={cls()}>x</p>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setCls("blue");
	assert mockToString(treeRoot) === mockToString(directRoot), "after set: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot).includes("blue"), "value moved: " + mockToString(directRoot);
	assert (directRoot as MockNode).children[0].attrs.length === 1, "upsert — no duplicate attr entries";
}

test "typed style channel through direct matches tree" {
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div style={dsheet.box}><p>a</p></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div style={dsheet.box}><p>a</p></div>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "markup: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	const tDiv = (treeRoot as MockNode).children[0];
	const dDiv = (directRoot as MockNode).children[0];
	assert tDiv.style !== null, "tree style set";
	assert dDiv.style !== null, "direct style set";
	assert tDiv.style === dDiv.style, "same Style object through both channels";
}

test "static attr + reactive attr + event + style mixed on one element" {
	const [n, setN] = createSignal<number>(0);
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<button type="button" title={n().toString()} style={dsheet.box} onClick={() => setN(n() + 1)}>go</button>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<button type="button" title={n().toString()} style={dsheet.box} onClick={() => setN(n() + 1)}>go</button>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	const dBtn = (directRoot as MockNode).children[0];
	fireEvent(dBtn, "onClick");
	assert mockToString(treeRoot) === mockToString(directRoot), "after click: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot).includes("title=\"1\""), "reactive attr moved: " + mockToString(directRoot);
	assert dBtn.style !== null, "style set on mixed element";
	assert dBtn.attrs.length === 2, "type + title only, no dup, got " + dBtn.attrs.length.toString();
}

test "deep interleave: dyn attr + dyn text + event across 4 levels" {
	const [cls, setCls] = createSignal("a");
	const [v, setV] = createSignal("t");
	let hits = 0;
	const bump = () => { hits = hits + 1; };
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div id="top"><section class={cls()}><ul><li>{v()}</li><li><button onClick={bump} title={cls()}>go {v()}</button></li></ul><p>tail</p></section></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div id="top"><section class={cls()}><ul><li>{v()}</li><li><button onClick={bump} title={cls()}>go {v()}</button></li></ul><p>tail</p></section></div>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setCls("b");
	assert mockToString(treeRoot) === mockToString(directRoot), "after setCls: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setV("u");
	assert mockToString(treeRoot) === mockToString(directRoot), "after setV: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot).includes("title=\"b\"") && mockToString(directRoot).includes("go u"), "values moved: " + mockToString(directRoot);
	const btn = (directRoot as MockNode).children[0].children[0].children[0].children[1].children[0];
	fireEvent(btn, "onClick");
	assert hits === 1, "event at depth 4 fired, hits=" + hits.toString();
}

// ---- D4: template-clone emission mode ----

// Counts element construction so a test can tell the template path (build once,
// clone per mount) from the flat path (build every mount).
function countingHost(counter: number[]): Host {
	const h = mockHost();
	return {
		createElement: (tag: string): HostNode => {
			counter[0] = counter[0] + 1;
			return h.createElement(tag);
		},
		createText: h.createText, setText: h.setText, setAttr: h.setAttr,
		setStyle: h.setStyle, setStyleProp: h.setStyleProp, setStyleClass: h.setStyleClass, addEvent: h.addEvent, append: h.append,
		insertBefore: h.insertBefore, removeChild: h.removeChild,
		nextSibling: h.nextSibling, firstChild: h.firstChild, cloneNode: h.cloneNode,
	};
}

test "template mode: a pure subtree is built once and cloned per mount" {
	const [v, setV] = createSignal("a");
	const counter: number[] = [0];
	const host = countingHost(counter);

	const mount = direct(<div class="box"><span>s</span><em>{v()}</em></div>);
	assert counter[0] === 0, "no work before the first mount, got " + counter[0].toString();

	const root = mockNode("root");
	host.append(root as unknown as HostNode, mount(host));
	const afterFirst = counter[0];
	assert afterFirst === 3, "template built once: div+span+em = 3 createElement, got " + afterFirst.toString();

	host.append(root as unknown as HostNode, mount(host));
	assert counter[0] === afterFirst, "second mount must CLONE, not rebuild — createElement went " + afterFirst.toString() + " -> " + counter[0].toString();

	assert mockToString(root) === "<root><div class=\"box\"><span>s</span><em>a</em></div><div class=\"box\"><span>s</span><em>a</em></div></root>", "two independent instances: " + mockToString(root);
	setV("b");
	assert mockToString(root) === "<root><div class=\"box\"><span>s</span><em>b</em></div><div class=\"box\"><span>s</span><em>b</em></div></root>", "every clone stays reactive: " + mockToString(root);
}

// Counts host text writes, so a test can separate a real update from a redundant
// touch. mockToString cannot see this: the tree state is identical either way.
function textCountingHost(counter: number[]): Host {
	const h = mockHost();
	return {
		createElement: h.createElement, createText: h.createText,
		setText: (node: HostNode, value: string): void => {
			counter[0] = counter[0] + 1;
			h.setText(node, value);
		},
		setAttr: h.setAttr, setStyle: h.setStyle, setStyleProp: h.setStyleProp, setStyleClass: h.setStyleClass, addEvent: h.addEvent,
		append: h.append, insertBefore: h.insertBefore, removeChild: h.removeChild,
		nextSibling: h.nextSibling, firstChild: h.firstChild, cloneNode: h.cloneNode,
	};
}

test "a spot recomputing to the same string writes the host once — tree emission" {
	const [n, setN] = createSignal<number>(1);
	const counter: number[] = [0];
	const host = textCountingHost(counter);
	const root = mockNode("root");

	const tv: NeonNode = element(<p>{n() > 5 ? "big" : "small"}</p>);
	renderToHost(tv, host, root as unknown as HostNode);
	assert counter[0] === 1, "one write at mount, got " + counter[0].toString();

	setN(2);
	assert counter[0] === 1, "source changed but the derived text did not — no host touch; got " + counter[0].toString();

	setN(9);
	assert counter[0] === 2, "a real change still writes, got " + counter[0].toString();
	assert mockToString(root) === "<root><p>big</p></root>", "value: " + mockToString(root);
}

test "a spot recomputing to the same string writes the host once — direct emission" {
	const [n, setN] = createSignal<number>(1);
	const counter: number[] = [0];
	const host = textCountingHost(counter);
	const root = mockNode("root");

	const mount = direct(<p>{n() > 5 ? "big" : "small"}</p>);
	host.append(root as unknown as HostNode, mount(host));
	assert counter[0] === 1, "one write at mount, got " + counter[0].toString();

	setN(2);
	assert counter[0] === 1, "source changed but the derived text did not — no host touch; got " + counter[0].toString();

	setN(9);
	assert counter[0] === 2, "a real change still writes, got " + counter[0].toString();
	assert mockToString(root) === "<root><p>big</p></root>", "value: " + mockToString(root);
}

test "a spot with no call and no property access renders the same through both emissions" {
	const label = "hi";
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<p class={label}>{label}</p>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<p class={label}>{label}</p>);
	host.append(directRoot as unknown as HostNode, mount(host));

	assert mockToString(treeRoot) === mockToString(directRoot), "same markup: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(treeRoot) === "<root><p class=\"hi\">hi</p></root>", "value: " + mockToString(treeRoot);
}

test "template mode on a cloneNode:null host falls back and still matches tree" {
	const [v, setV] = createSignal("a");
	const base = mockHost();
	const host: Host = {
		createElement: base.createElement, createText: base.createText, setText: base.setText,
		setAttr: base.setAttr, setStyle: base.setStyle, setStyleProp: base.setStyleProp, setStyleClass: base.setStyleClass, addEvent: base.addEvent,
		append: base.append, insertBefore: base.insertBefore, removeChild: base.removeChild,
		nextSibling: base.nextSibling, firstChild: base.firstChild,
		cloneNode: null,
	};

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<ul class="l"><li>{v()}</li><li>x</li></ul>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<ul class="l"><li>{v()}</li><li>x</li></ul>);
	host.append(directRoot as unknown as HostNode, mount(host));

	assert mockToString(treeRoot) === mockToString(directRoot), "fallback initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setV("z");
	assert mockToString(treeRoot) === mockToString(directRoot), "fallback after set: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
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
