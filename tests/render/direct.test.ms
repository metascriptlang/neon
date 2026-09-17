// Direct emission V1 — differential against tree emission on the mock host:
// same JSX through both emissions must be byte-identical, before and after
// signal updates (tree emission is the oracle — docs/RENDER-MODEL.md).

import { createSignal, accessor, Accessor } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { element } from "../../src/macros/ui/element";
import { direct } from "../../src/macros/ui/direct";
import { NeonNode, el, attr } from "../../src/render/node";
import { createComponent } from "../../src/render/component";
import { Show, For } from "../../src/macros/ui/flow";
import { renderToHost, renderNode, mockHost, mockNode, mockToString, fireEvent, fireEventWith, bindText, bindAttr, MockNode, Host, HostNode, NeonView, viewOf } from "../../src/render/host";
import { createMemo } from "../../src/core/memo";
import { Style, layerStyles } from "../../src/render/style";
import { styleToCss } from "../../src/render/css";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createTemplate, mountTemplate, childOf, siblingOf } from "../../src/render/template";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { registerCss, resetCss, cssRuleCount } from "../../src/render/sheet";

test "static + dynamic text + event: direct matches tree" {
	const [name, setName] = createSignal("an");
	let clicks = 0;
	const inc: (e: NeonEvent) => void = () => { clicks = clicks + 1; };
	const host = mockHost();

	const treeRoot = mockNode("root");
	const view: NeonNode = element(<div class="box"><p>hello {name()}</p><button onPress={inc}>+</button></div>);
	renderToHost(view, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div class="box"><p>hello {name()}</p><button onPress={inc}>+</button></div>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setName("binh");
	assert mockToString(treeRoot) === mockToString(directRoot), "after set: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div class=\"box\"><p>hello binh</p><button>+</button></div></root>", "golden: " + mockToString(directRoot);

	const btn = (directRoot as MockNode).children[0].children[1];
	fireEvent(btn, "onPress");
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
	assert mockToString(directRoot) === "<root><ul><li><span>a</span></li><li>y</li></ul></root>", "golden: " + mockToString(directRoot);
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
	assert mockToString(directRoot) === "<root><div id=\"x\" class=\"y\"><p>7</p><p>9</p><span>7</span></div></root>", "golden: " + mockToString(directRoot);
}

// ---- D1: component tags + Show through direct emission (tree side = oracle) ----

interface GaugeProps {
	count: Accessor<number>;
	label: Accessor<string>;
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
	title: Accessor<string>;
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
	assert mockToString(directRoot) === "<root><div><p class=\"g\">n=9</p></div></root>", "golden: " + mockToString(directRoot);
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
	assert mockToString(directRoot) === "<root><p class=\"r\">n=4</p></root>", "golden: " + mockToString(directRoot);
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
	assert mockToString(directRoot) === "<root><div><p class=\"a\">n=102</p></div></root>", "golden: " + mockToString(directRoot);
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
	assert mockToString(directRoot) === "<root><div><i>1</i></div></root>", "golden: " + mockToString(directRoot);
	const dDiv = (directRoot as MockNode).children[0];
	assert dDiv.children.length === 2, "region span (child + anchor) under direct div, got " + dDiv.children.length.toString();
	setOn(false);
	assert leakRuns === 2, "one cleanup per emission on flip, got " + leakRuns.toString();
	assert mockToString(treeRoot) === mockToString(directRoot), "after flip: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div></div></root>", "golden after flip: " + mockToString(directRoot);
	setOn(true);
	assert mockToString(treeRoot) === mockToString(directRoot), "after flip back: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setN(7);
	assert mockToString(treeRoot) === mockToString(directRoot), "rebuilt child reactive: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div><i>7</i></div></root>", "golden after rebuild: " + mockToString(directRoot);
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
	assert mockToString(directRoot) === "<root><div><section title=\"t\"><p>inner</p></section></div></root>", "golden: " + mockToString(directRoot);
}

// ---- D2: attr classification + typed style through direct emission ----

const layerSheet = createStyles({
	box: { width: 200, height: 120 },
	row: { height: 20 },
});

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
	assert mockToString(directRoot) === "<root><p class=\"blue\">x</p></root>", "golden: " + mockToString(directRoot);
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
	assert mockToString(directRoot) === "<root><div><p>a</p></div></root>", "golden: " + mockToString(directRoot);
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
	const tv: NeonNode = element(<button type="button" title={n().toString()} style={dsheet.box} onPress={() => setN(n() + 1)}>go</button>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<button type="button" title={n().toString()} style={dsheet.box} onPress={() => setN(n() + 1)}>go</button>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	const dBtn = (directRoot as MockNode).children[0];
	fireEvent(dBtn, "onPress");
	assert mockToString(treeRoot) === mockToString(directRoot), "after click: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><button type=\"button\" title=\"1\">go</button></root>", "golden: " + mockToString(directRoot);
	assert dBtn.style !== null, "style set on mixed element";
	assert dBtn.attrs.length === 2, "type + title only, no dup, got " + dBtn.attrs.length.toString();
}

test "deep interleave: dyn attr + dyn text + event across 4 levels" {
	const [cls, setCls] = createSignal("a");
	const [v, setV] = createSignal("t");
	let hits = 0;
	const bump: (e: NeonEvent) => void = () => { hits = hits + 1; };
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div id="top"><section class={cls()}><ul><li>{v()}</li><li><button onPress={bump} title={cls()}>go {v()}</button></li></ul><p>tail</p></section></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div id="top"><section class={cls()}><ul><li>{v()}</li><li><button onPress={bump} title={cls()}>go {v()}</button></li></ul><p>tail</p></section></div>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setCls("b");
	assert mockToString(treeRoot) === mockToString(directRoot), "after setCls: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setV("u");
	assert mockToString(treeRoot) === mockToString(directRoot), "after setV: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div id=\"top\"><section class=\"b\"><ul><li>u</li><li><button title=\"b\">go u</button></li></ul><p>tail</p></section></div></root>", "golden: " + mockToString(directRoot);
	const btn = (directRoot as MockNode).children[0].children[0].children[0].children[1].children[0];
	fireEvent(btn, "onPress");
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
	assert mockToString(directRoot) === "<root><ul class=\"l\"><li>z</li><li>x</li></ul></root>", "golden: " + mockToString(directRoot);
}

test "For reorder through direct matches tree" {
	const [items, setItems] = createSignal<number[]>([1, 2, 3]);
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<ul><For each={items()}>{(item: number, i: () => number): NeonView => viewOf(element(<li>{item.toString()}</li>))}</For></ul>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<ul><For each={items()}>{(item: number, i: () => number): NeonView => viewOf(element(<li>{item.toString()}</li>))}</For></ul>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setItems([3, 1, 2]);
	assert mockToString(treeRoot) === mockToString(directRoot), "after reorder: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><ul><li>3</li><li>1</li><li>2</li></ul></root>", "golden after reorder: " + mockToString(directRoot);
	setItems([3, 1, 2, 4]);
	assert mockToString(treeRoot) === mockToString(directRoot), "after append: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setItems([2]);
	assert mockToString(treeRoot) === mockToString(directRoot), "after shrink: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><ul><li>2</li></ul></root>", "golden after shrink: " + mockToString(directRoot);
}

test "a && <X/> through direct matches tree" {
	const [on, setOn] = createSignal(true);
	const host = mockHost();
	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div><p>a</p>{on && <span>yes</span>}<p>z</p></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);
	const directRoot = mockNode("root");
	const mount = direct(<div><p>a</p>{on && <span>yes</span>}<p>z</p></div>);
	host.append(directRoot as unknown as HostNode, mount(host));
	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div><p>a</p><span>yes</span><p>z</p></div></root>", "golden while true: " + mockToString(directRoot);
	setOn(false);
	assert mockToString(treeRoot) === mockToString(directRoot), "after off: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div><p>a</p><p>z</p></div></root>", "golden while false: " + mockToString(directRoot);
	setOn(true);
	assert mockToString(treeRoot) === mockToString(directRoot), "after on: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
}

test "c ? <A/> : <B/> through direct matches tree" {
	const [on, setOn] = createSignal(false);
	const host = mockHost();
	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div>{on ? <span>yes</span> : <b>no</b>}</div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);
	const directRoot = mockNode("root");
	const mount = direct(<div>{on ? <span>yes</span> : <b>no</b>}</div>);
	host.append(directRoot as unknown as HostNode, mount(host));
	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div><b>no</b></div></root>", "golden false state: " + mockToString(directRoot);
	setOn(true);
	assert mockToString(treeRoot) === mockToString(directRoot), "after on: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div><span>yes</span></div></root>", "golden true state: " + mockToString(directRoot);
}

test "xs.map(row) through direct matches tree" {
	const [items, setItems] = createSignal<number[]>([1, 2, 3]);
	const host = mockHost();
	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<ul>{items.map((n: number): NeonView => viewOf(element(<li>{n.toString()}</li>)))}</ul>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);
	const directRoot = mockNode("root");
	const mount = direct(<ul>{items.map((n: number): NeonView => viewOf(element(<li>{n.toString()}</li>)))}</ul>);
	host.append(directRoot as unknown as HostNode, mount(host));
	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setItems([3, 1, 2, 4]);
	assert mockToString(treeRoot) === mockToString(directRoot), "after change: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><ul><li>3</li><li>1</li><li>2</li><li>4</li></ul></root>", "golden: " + mockToString(directRoot);
}

interface BareTagProps {
	label: Accessor<string>;
}

function BareTag(props: BareTagProps): NeonNode {
	return element(<b>{props.label}</b>);
}

test "a bare accessor attribute and child through direct match tree" {
	const [l, setL] = createSignal("a");
	const host = mockHost();
	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<p class={l}>{l}</p>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);
	const directRoot = mockNode("root");
	const mount = direct(<p class={l}>{l}</p>);
	host.append(directRoot as unknown as HostNode, mount(host));
	setL("b");
	assert mockToString(treeRoot) === mockToString(directRoot), "after set: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><p class=\"b\">b</p></root>", "value: " + mockToString(directRoot);
}

test "an accessor operand, a bare child and an accessor prop beside a component through direct match tree" {
	const [l, setL] = createSignal("a");
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();
	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div title={(n * 2).toString()}>{l}<BareTag label={l} /></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);
	const directRoot = mockNode("root");
	const mount = direct(<div title={(n * 2).toString()}>{l}<BareTag label={l} /></div>);
	host.append(directRoot as unknown as HostNode, mount(host));
	setL("b");
	setN(4);
	assert mockToString(treeRoot) === mockToString(directRoot), "after set: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div title=\"8\">b<b>b</b></div></root>", "golden: " + mockToString(directRoot);
}

// ---- D3 flat emission: lowercase siblings beside a component tag ----

test "static attr, static text, event and ref beside a component through direct match tree" {
	const [n, setN] = createSignal<number>(1);
	let treeHits = 0;
	let directHits = 0;
	let treeSeen = "";
	let directSeen = "";
	const treeBump: (e: NeonEvent) => void = () => { treeHits = treeHits + 1; };
	const directBump: (e: NeonEvent) => void = () => { directHits = directHits + 1; };
	const treeGrab: (b: HostNode) => void = (b) => { treeSeen = mockToString(b as unknown as MockNode); };
	const directGrab: (b: HostNode) => void = (b) => { directSeen = mockToString(b as unknown as MockNode); };
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div id="top" class="c"><Gauge count={n()} label="g" /><button type="button" onPress={treeBump} ref={treeGrab}>go</button><p>tail</p></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div id="top" class="c"><Gauge count={n()} label="g" /><button type="button" onPress={directBump} ref={directGrab}>go</button><p>tail</p></div>);
	host.append(directRoot as unknown as HostNode, mount(host));

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div id=\"top\" class=\"c\"><p class=\"g\">n=1</p><button type=\"button\">go</button><p>tail</p></div></root>", "golden: " + mockToString(directRoot);
	assert treeSeen === "<button type=\"button\">go</button>", "tree ref saw the finished node: " + treeSeen;
	assert directSeen === treeSeen, "direct ref saw the same node: " + directSeen;

	fireEvent((treeRoot as MockNode).children[0].children[1], "onPress");
	fireEvent((directRoot as MockNode).children[0].children[1], "onPress");
	assert treeHits === 1 && directHits === 1, "one hit each: tree=" + treeHits.toString() + " direct=" + directHits.toString();

	setN(5);
	assert mockToString(treeRoot) === mockToString(directRoot), "after set: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div id=\"top\" class=\"c\"><p class=\"g\">n=5</p><button type=\"button\">go</button><p>tail</p></div></root>", "golden after set: " + mockToString(directRoot);
}

test "onChangeText beside a component hands the handler the text on both emissions" {
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();

	const treeRoot = mockNode("root");
	let treeText = "";
	renderToHost(element(<div><Gauge count={n()} label="g" /><input onChangeText={(t: string): void => { treeText = t; }} /></div>), host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	let directText = "";
	const mount = direct(<div><Gauge count={n()} label="g" /><input onChangeText={(t: string): void => { directText = t; }} /></div>);
	host.append(directRoot as unknown as HostNode, mount(host));

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div><p class=\"g\">n=1</p><input></input></div></root>", "golden: " + mockToString(directRoot);

	const e = neonEvent("changetext");
	e.value = "xin chao";
	fireEventWith((treeRoot as MockNode).children[0].children[1], "onChangeText", e);
	fireEventWith((directRoot as MockNode).children[0].children[1], "onChangeText", e);
	assert treeText === "xin chao", "tree read text=" + treeText;
	assert directText === "xin chao", "direct read text=" + directText;
}

test "a ternary with a null arm through direct matches tree, either way round" {
	const [on, setOn] = createSignal(true);
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div>{on ? <span>yes</span> : null}<p>m</p>{on ? null : <b>no</b>}</div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div>{on ? <span>yes</span> : null}<p>m</p>{on ? null : <b>no</b>}</div>);
	host.append(directRoot as unknown as HostNode, mount(host));

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div><span>yes</span><p>m</p></div></root>", "golden while true: " + mockToString(directRoot);
	setOn(false);
	assert mockToString(treeRoot) === mockToString(directRoot), "after off: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div><p>m</p><b>no</b></div></root>", "golden while false: " + mockToString(directRoot);
	setOn(true);
	assert mockToString(treeRoot) === mockToString(directRoot), "after on: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div><span>yes</span><p>m</p></div></root>", "golden back on: " + mockToString(directRoot);
}

// ---- S13: a whole-style expression that reads a signal is one effect on both emissions ----

function cssAt(root: MockNode, i: number): string {
	const st = root.children[i].style;
	return st === null ? "(none)" : styleToCss(st as Style);
}

test "a whole-style call through direct tracks the signal like tree — template tier" {
	const [pad, setPad] = createSignal<number>(10);
	const s = (): Style => { const st: Style = { padding: pad() }; return st; };
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div style={s()}><p>a</p></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div style={s()}><p>a</p></div>);
	host.append(directRoot as unknown as HostNode, mount(host));

	assert mockToString(treeRoot) === mockToString(directRoot), "markup: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "initial: tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	assert cssAt(directRoot, 0) === "padding:10px;", "golden: " + cssAt(directRoot, 0);
	setPad(20);
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "after set: tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	assert cssAt(directRoot, 0) === "padding:20px;", "golden after set: " + cssAt(directRoot, 0);
}

test "a whole-style call through direct tracks the signal like tree — flat tier" {
	const [pad, setPad] = createSignal<number>(10);
	const [n, setN] = createSignal<number>(1);
	const s = (): Style => { const st: Style = { padding: pad() }; return st; };
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div style={s()}><Gauge count={n()} label="g" /></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div style={s()}><Gauge count={n()} label="g" /></div>);
	host.append(directRoot as unknown as HostNode, mount(host));

	assert mockToString(treeRoot) === mockToString(directRoot), "markup: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert cssAt(directRoot, 0) === "padding:10px;", "golden: " + cssAt(directRoot, 0);
	setPad(20);
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "after set: tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	assert cssAt(directRoot, 0) === "padding:20px;", "golden after set: " + cssAt(directRoot, 0);
}

test "an accessor-typed style and a ternary style through direct track the signal like tree" {
	const [pad, setPad] = createSignal<number>(10);
	const [n, setN] = createSignal<number>(1);
	const memoStyle = createMemo((): Style => { const st: Style = { padding: pad() }; return st; });
	const small: Style = { margin: 1 };
	const big: Style = { margin: 2 };
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div><p style={memoStyle}>a</p><p style={pad() > 15 ? big : small}>b</p><Gauge count={n()} label="g" /></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div><p style={memoStyle}>a</p><p style={pad() > 15 ? big : small}>b</p><Gauge count={n()} label="g" /></div>);
	host.append(directRoot as unknown as HostNode, mount(host));

	const tDiv = (treeRoot as MockNode).children[0];
	const dDiv = (directRoot as MockNode).children[0];
	assert mockToString(treeRoot) === mockToString(directRoot), "markup: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert cssAt(dDiv, 0) === "padding:10px;" && cssAt(dDiv, 1) === "margin:1px;", "golden: " + cssAt(dDiv, 0) + " " + cssAt(dDiv, 1);
	setPad(20);
	assert cssAt(tDiv, 0) === cssAt(dDiv, 0), "accessor style after set: tree=" + cssAt(tDiv, 0) + " direct=" + cssAt(dDiv, 0);
	assert cssAt(tDiv, 1) === cssAt(dDiv, 1), "ternary style after set: tree=" + cssAt(tDiv, 1) + " direct=" + cssAt(dDiv, 1);
	assert cssAt(dDiv, 0) === "padding:20px;" && cssAt(dDiv, 1) === "margin:2px;", "golden after set: " + cssAt(dDiv, 0) + " " + cssAt(dDiv, 1);
}

// ---- Lát 0.2: a reactive style FIELD is one per-property effect on both emissions ----

test "reactive style fields through direct track their signals like tree — template tier" {
	const [w, setW] = createSignal<number>(10);
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div style={{ padding: w(), height: n() * 10, margin: 4 }}><p>a</p></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div style={{ padding: w(), height: n() * 10, margin: 4 }}><p>a</p></div>);
	host.append(directRoot as unknown as HostNode, mount(host));

	assert mockToString(treeRoot) === mockToString(directRoot), "markup: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "initial: tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	assert cssAt(directRoot, 0) === "height:10px;margin:4px;padding:10px;", "golden: " + cssAt(directRoot, 0);
	setW(20);
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "after setW: tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	setN(3);
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "after setN: tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	assert cssAt(directRoot, 0) === "height:30px;margin:4px;padding:20px;", "golden after set: " + cssAt(directRoot, 0);
}

test "a ternary style field and a bare accessor field through direct track the signal like tree — flat tier" {
	const [pad, setPad] = createSignal<number>(10);
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div><p style={{ margin: pad() > 15 ? 2 : 1 }}>a</p><p style={{ padding: pad }}>b</p><Gauge count={n()} label="g" /></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div><p style={{ margin: pad() > 15 ? 2 : 1 }}>a</p><p style={{ padding: pad }}>b</p><Gauge count={n()} label="g" /></div>);
	host.append(directRoot as unknown as HostNode, mount(host));

	const tDiv = (treeRoot as MockNode).children[0];
	const dDiv = (directRoot as MockNode).children[0];
	assert mockToString(treeRoot) === mockToString(directRoot), "markup: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert cssAt(dDiv, 0) === "margin:1px;" && cssAt(dDiv, 1) === "padding:10px;", "golden: " + cssAt(dDiv, 0) + " " + cssAt(dDiv, 1);
	setPad(20);
	assert cssAt(tDiv, 0) === cssAt(dDiv, 0), "ternary field after set: tree=" + cssAt(tDiv, 0) + " direct=" + cssAt(dDiv, 0);
	assert cssAt(tDiv, 1) === cssAt(dDiv, 1), "bare accessor field after set: tree=" + cssAt(tDiv, 1) + " direct=" + cssAt(dDiv, 1);
	assert cssAt(dDiv, 0) === "margin:2px;" && cssAt(dDiv, 1) === "padding:20px;", "golden after set: " + cssAt(dDiv, 0) + " " + cssAt(dDiv, 1);
}

test "a bare accessor style field through direct — template tier" {
	const [w, setW] = createSignal<number>(10);
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div style={{ padding: w }}><p>a</p></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div style={{ padding: w }}><p>a</p></div>);
	host.append(directRoot as unknown as HostNode, mount(host));

	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "initial: tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	setW(20);
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "after set: tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	assert cssAt(directRoot, 0) === "padding:20px;", "golden after set: " + cssAt(directRoot, 0);
}

test "an identical signal value on a direct style field is not re-written to the host" {
	const [w, setW] = createSignal<number>(20);
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = direct(<div style={{ width: w() }}><p>a</p></div>);
	host.append(directRoot as unknown as HostNode, mount(host));
	const div = (directRoot as MockNode).children[0];
	const before = div.style;
	setW(20);
	assert div.style === before, "same value writes nothing";
	assert (div.style as Style).width === 20, "value intact";
}

test "an all-static style object through direct lands as one constant on both tiers" {
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div style={{ width: 200, height: 120 }}><p style={{ margin: 3, color: "red" }}>a</p><Gauge count={n()} label="g" /></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div style={{ width: 200, height: 120 }}><p style={{ margin: 3, color: "red" }}>a</p><Gauge count={n()} label="g" /></div>);
	host.append(directRoot as unknown as HostNode, mount(host));

	const tDiv = (treeRoot as MockNode).children[0];
	const dDiv = (directRoot as MockNode).children[0];
	assert mockToString(treeRoot) === mockToString(directRoot), "markup: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "outer: tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	assert cssAt(tDiv, 0) === cssAt(dDiv, 0), "inner: tree=" + cssAt(tDiv, 0) + " direct=" + cssAt(dDiv, 0);
	assert cssAt(directRoot, 0) === "width:200px;height:120px;", "golden outer: " + cssAt(directRoot, 0);
	assert cssAt(dDiv, 0) === "margin:3px;color:red;", "golden inner: " + cssAt(dDiv, 0);
}

test "an all-static style object through direct — template tier" {
	const host = mockHost();
	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div style={{ padding: 5 }}><p>a</p></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);
	const directRoot = mockNode("root");
	const mount = direct(<div style={{ padding: 5 }}><p>a</p></div>);
	host.append(directRoot as unknown as HostNode, mount(host));
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	assert cssAt(directRoot, 0) === "padding:5px;", "golden: " + cssAt(directRoot, 0);
}

// ---- Lát 0.4: style layer arrays on both emissions ----

test "all-literal style layers merge at expansion through direct like tree — template tier" {
	const host = mockHost();
	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div style={[{ width: 200, height: 120 }, { height: 20 }]}><p>a</p></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);
	const directRoot = mockNode("root");
	const mount = direct(<div style={[{ width: 200, height: 120 }, { height: 20 }]}><p>a</p></div>);
	host.append(directRoot as unknown as HostNode, mount(host));
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	assert cssAt(directRoot, 0) === "width:200px;height:20px;", "golden: " + cssAt(directRoot, 0);
}

test "a null field in a later literal layer keeps the earlier value through direct like tree — flat tier" {
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();
	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div style={[{ width: 1, height: 5 }, { height: null }, { width: 3 }]}><Gauge count={n()} label="g" /></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);
	const directRoot = mockNode("root");
	const mount = direct(<div style={[{ width: 1, height: 5 }, { height: null }, { width: 3 }]}><Gauge count={n()} label="g" /></div>);
	host.append(directRoot as unknown as HostNode, mount(host));
	assert mockToString(treeRoot) === mockToString(directRoot), "markup: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	assert cssAt(directRoot, 0) === "width:3px;height:5px;", "golden: " + cssAt(directRoot, 0);
}

test "a sheet layer under a literal override goes through layerStyles on direct like tree — template tier" {
	const host = mockHost();
	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div style={[layerSheet.box, { height: 20 }]}><p>a</p></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);
	const directRoot = mockNode("root");
	const mount = direct(<div style={[layerSheet.box, { height: 20 }]}><p>a</p></div>);
	host.append(directRoot as unknown as HostNode, mount(host));
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	assert cssAt(directRoot, 0) === "width:200px;height:20px;", "golden: " + cssAt(directRoot, 0);
}

test "two sheet layers go through layerStyles on direct like tree — flat tier" {
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();
	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div style={[layerSheet.box, layerSheet.row]}><Gauge count={n()} label="g" /></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);
	const directRoot = mockNode("root");
	const mount = direct(<div style={[layerSheet.box, layerSheet.row]}><Gauge count={n()} label="g" /></div>);
	host.append(directRoot as unknown as HostNode, mount(host));
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	assert cssAt(directRoot, 0) === "width:200px;height:20px;", "golden: " + cssAt(directRoot, 0);
}

// ---- Lát 0.5: a static sheet entry takes the class route on a host with a stylesheet ----

function cssHost(): Host {
	const h = mockHost();
	h.setStyleClass = (node: HostNode, id: string, css: string): void => {
		registerCss(id, css);
		(node as unknown as MockNode).className = id;
	};
	return h;
}

test "a static sheet entry through direct takes the class route like tree — template tier" {
	resetCss();
	const host = cssHost();
	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div style={dsheet.box}><p>a</p></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);
	const directRoot = mockNode("root");
	const mount = direct(<div style={dsheet.box}><p>a</p></div>);
	host.append(directRoot as unknown as HostNode, mount(host));
	const tDiv = (treeRoot as MockNode).children[0];
	const dDiv = (directRoot as MockNode).children[0];
	assert tDiv.className === dDiv.className, "class: tree=" + tDiv.className + " direct=" + dDiv.className;
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "inline: tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	when (js) {
		assert dDiv.className === (dsheet.box.cssId as string), "golden class: " + dDiv.className;
		assert dDiv.style === null, "no inline style once a class applies";
		assert cssRuleCount() === 1, "one rule shared by tree and direct, got " + cssRuleCount().toString();
	} else {
		assert dDiv.className === "", "no class off the browser lane";
		assert cssAt(directRoot, 0) === "width:40px;height:10px;", "golden native inline: " + cssAt(directRoot, 0);
	}
}

test "a static sheet entry through direct takes the class route like tree — flat tier" {
	resetCss();
	const [n, setN] = createSignal<number>(1);
	const host = cssHost();
	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div style={dsheet.box}><Gauge count={n()} label="g" /></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);
	const directRoot = mockNode("root");
	const mount = direct(<div style={dsheet.box}><Gauge count={n()} label="g" /></div>);
	host.append(directRoot as unknown as HostNode, mount(host));
	const tDiv = (treeRoot as MockNode).children[0];
	const dDiv = (directRoot as MockNode).children[0];
	assert mockToString(treeRoot) === mockToString(directRoot), "markup: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert tDiv.className === dDiv.className, "class: tree=" + tDiv.className + " direct=" + dDiv.className;
	when (js) {
		assert dDiv.className === (dsheet.box.cssId as string), "golden class: " + dDiv.className;
		assert dDiv.style === null, "no inline style once a class applies";
	} else {
		assert cssAt(directRoot, 0) === "width:40px;height:10px;", "golden native inline: " + cssAt(directRoot, 0);
	}
}

// ---- Lát 0.6: a static {node} child mounts as a node on both emissions ----

test "a static node child through direct mounts like tree" {
	const host = mockHost();
	const kid: NeonNode = element(<b>k</b>);
	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div><p>a</p>{kid}<p>z</p></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);
	const directRoot = mockNode("root");
	const kid2: NeonNode = element(<b>k</b>);
	const mount = direct(<div><p>a</p>{kid2}<p>z</p></div>);
	host.append(directRoot as unknown as HostNode, mount(host));
	assert mockToString(treeRoot) === mockToString(directRoot), "markup: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot) === "<root><div><p>a</p><b>k</b><p>z</p></div></root>", "golden: " + mockToString(directRoot);
}

interface FrameProps {
	title: string;
	children: NeonNode;
}

function Frame(props: FrameProps): NeonView {
	return direct(<section title={props.title}>{props.children}</section>);
}

test "{props.children} carrying a node with live text through direct tracks the signal" {
	const [name, setName] = createSignal("an");
	const host = mockHost();
	const directRoot = mockNode("root");
	const view = Frame({ title: "t", children: element(<p>hi {name()}</p>) });
	host.append(directRoot as unknown as HostNode, view(host));
	assert mockToString(directRoot) === "<root><section title=\"t\"><p>hi an</p></section></root>", "golden: " + mockToString(directRoot);
	setName("binh");
	assert mockToString(directRoot) === "<root><section title=\"t\"><p>hi binh</p></section></root>", "golden after set: " + mockToString(directRoot);
}

// ---- Lát 0.8: a reactive layer is rejected; the escape hatch is a whole-style layerStyles call ----

test "layerStyles over a reactive layer as a whole-style expression tracks the signal like tree" {
	const [h, setH] = createSignal<number>(5);
	const pick = (): Style => { const s: Style = { height: h() }; return s; };
	const host = mockHost();
	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div style={layerStyles([layerSheet.box, pick()])}><p>a</p></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);
	const directRoot = mockNode("root");
	const mount = direct(<div style={layerStyles([layerSheet.box, pick()])}><p>a</p></div>);
	host.append(directRoot as unknown as HostNode, mount(host));
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "initial: tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	assert cssAt(directRoot, 0) === "width:200px;height:5px;", "golden: " + cssAt(directRoot, 0);
	setH(9);
	assert cssAt(treeRoot, 0) === cssAt(directRoot, 0), "after set: tree=" + cssAt(treeRoot, 0) + " direct=" + cssAt(directRoot, 0);
	assert cssAt(directRoot, 0) === "width:200px;height:9px;", "golden after set: " + cssAt(directRoot, 0);
}
