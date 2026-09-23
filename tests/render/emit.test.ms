// What the element macro emits, pinned on the mock host by hand-written goldens:
// the flat tier, the template-clone tier, and the spots each one keeps live.

import { createSignal, accessor, Accessor } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { element } from "../../src/macros/ui/element";
import { NeonNode, el, attr } from "../../src/render/node";
import { createComponent } from "../../src/render/component";
import { Show, For } from "../../src/macros/ui/flow";
import { render, mockHost, mockNode, mockToString, fireEvent, fireEventWith, bindText, bindAttr, MockNode, Host, HostNode } from "../../src/render/host";
import { createMemo } from "../../src/core/memo";
import { Style, layerStyles } from "../../src/render/style";
import { styleToCss } from "../../src/render/css";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createTemplate, mountTemplate, childOf, siblingOf } from "../../src/render/template";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { registerCss, resetCss, cssRuleCount } from "../../src/render/sheet";

test "static + dynamic text + event" {
	const [name, setName] = createSignal("an");
	let clicks = 0;
	const inc: (e: NeonEvent) => void = () => { clicks = clicks + 1; };
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div class="box"><p>hello {name()}</p><button onPress={inc}>+</button></div>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><div class=\"box\"><p>hello an</p><button>+</button></div></root>", "initial: " + mockToString(directRoot);
	setName("binh");
	assert mockToString(directRoot) === "<root><div class=\"box\"><p>hello binh</p><button>+</button></div></root>", "golden: " + mockToString(directRoot);

	const btn = (directRoot as MockNode).children[0].children[1];
	fireEvent(btn, "onPress");
	assert clicks === 1, "clicks=" + clicks.toString();
}

test "deep nesting" {
	const [v, setV] = createSignal("x");
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<ul><li><span>a</span></li><li>{v()}</li></ul>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><ul><li><span>a</span></li><li>x</li></ul></root>", "initial: " + mockToString(directRoot);
	setV("y");
	assert mockToString(directRoot) === "<root><ul><li><span>a</span></li><li>y</li></ul></root>", "golden: " + mockToString(directRoot);
}

test "multiple attrs and multiple dynamic spots keep distinct temps" {
	const [a, setA] = createSignal("1");
	const [b, setB] = createSignal("2");
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div id="x" class="y"><p>{a()}</p><p>{b()}</p><span>{a()}</span></div>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><div id=\"x\" class=\"y\"><p>1</p><p>2</p><span>1</span></div></root>", "initial: " + mockToString(directRoot);
	setA("7");
	assert mockToString(directRoot) === "<root><div id=\"x\" class=\"y\"><p>7</p><p>2</p><span>7</span></div></root>", "after setA: " + mockToString(directRoot);
	setB("9");
	assert mockToString(directRoot) === "<root><div id=\"x\" class=\"y\"><p>7</p><p>9</p><span>7</span></div></root>", "golden: " + mockToString(directRoot);
}

// ---- D1: component tags + Show ----

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
	return <section title={props.title()}>{props.children}</section>;
}

function applyFn(f: () => number): number { return f(); }

test "component child: defer, bodyRuns once, reactive prop updates" {
	gaugeRuns = 0;
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div><Gauge count={n()} label="g" /></div>);
	assert gaugeRuns === 0, "element() must not run the body before mount, got " + gaugeRuns.toString();
	mount(host, directRoot as unknown as HostNode, null);
	assert gaugeRuns === 1, "one body run at mount, got " + gaugeRuns.toString();

	assert mockToString(directRoot) === "<root><div><p class=\"g\">n=1</p></div></root>", "initial: " + mockToString(directRoot);
	setN(5);
	assert mockToString(directRoot) === "<root><div><p class=\"g\">n=5</p></div></root>", "after set: " + mockToString(directRoot);
	setN(9);
	assert mockToString(directRoot) === "<root><div><p class=\"g\">n=9</p></div></root>", "after 2nd set: " + mockToString(directRoot);
	assert gaugeRuns === 1, "sets must not re-run bodies, got " + gaugeRuns.toString();
}

test "root-position component: deferred until mount" {
	gaugeRuns = 0;
	const [n, setN] = createSignal<number>(3);
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<Gauge count={n()} label="r" />);
	assert gaugeRuns === 0, "root component body deferred until mount, got " + gaugeRuns.toString();
	mount(host, directRoot as unknown as HostNode, null);
	assert gaugeRuns === 1, "body ran once at mount, got " + gaugeRuns.toString();

	assert mockToString(directRoot) === "<root><p class=\"r\">n=3</p></root>", "initial: " + mockToString(directRoot);
	setN(4);
	assert mockToString(directRoot) === "<root><p class=\"r\">n=4</p></root>", "golden: " + mockToString(directRoot);
}

test "prop expression with a nested arrow capturing outer variables stays reactive" {
	const base: number = 100;
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div><Gauge count={applyFn(() => n() + base)} label="a" /></div>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><div><p class=\"a\">n=101</p></div></root>", "initial: " + mockToString(directRoot);
	setN(2);
	assert mockToString(directRoot) === "<root><div><p class=\"a\">n=102</p></div></root>", "golden: " + mockToString(directRoot);
}

test "Show flip: cleanup fires, span on both flips" {
	leakRuns = 0;
	const [n, setN] = createSignal<number>(1);
	const [on, setOn] = createSignal(true);
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div><Show when={on()}><Leak count={n()} label="l" /></Show></div>);
	mount(host, directRoot as unknown as HostNode, null);

	assert leakRuns === 0, "no cleanup while mounted";
	assert mockToString(directRoot) === "<root><div><i>1</i></div></root>", "golden: " + mockToString(directRoot);
	const dDiv = (directRoot as MockNode).children[0];
	assert dDiv.children.length === 2, "region span (child + anchor) under direct div, got " + dDiv.children.length.toString();
	setOn(false);
	assert leakRuns === 1, "one cleanup on flip, got " + leakRuns.toString();
	assert mockToString(directRoot) === "<root><div></div></root>", "golden after flip: " + mockToString(directRoot);
	setOn(true);
	assert mockToString(directRoot) === "<root><div><i>1</i></div></root>", "after flip back: " + mockToString(directRoot);
	setN(7);
	assert mockToString(directRoot) === "<root><div><i>7</i></div></root>", "golden after rebuild: " + mockToString(directRoot);
}

test "single element child passes as the children prop" {
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div><Card title="t"><p>inner</p></Card></div>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><div><section title=\"t\"><p>inner</p></section></div></root>", "golden: " + mockToString(directRoot);
}

// ---- D2: attr classification + typed style ----

const layerSheet = createStyles({
	box: { width: 200, height: 120 },
	row: { height: 20 },
});

const dsheet = createStyles({
	box: { width: 40, height: 10 },
});

test "reactive attr" {
	const [cls, setCls] = createSignal("red");
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<p class={cls()}>x</p>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><p class=\"red\">x</p></root>", "initial: " + mockToString(directRoot);
	setCls("blue");
	assert mockToString(directRoot) === "<root><p class=\"blue\">x</p></root>", "golden: " + mockToString(directRoot);
	assert (directRoot as MockNode).children[0].attrs.length === 1, "upsert — no duplicate attr entries";
}

test "typed style channel" {
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div style={dsheet.box}><p>a</p></div>);
	mount(host, directRoot as unknown as HostNode, null);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><div><p>a</p></div><div><p>a</p></div></root>", "golden: " + mockToString(directRoot);
	const first = (directRoot as MockNode).children[0];
	const second = (directRoot as MockNode).children[1];
	assert first.style !== null, "style set";
	assert first.style === second.style, "every mount hands the host the same Style object";
}

test "static attr + reactive attr + event + style mixed on one element" {
	const [n, setN] = createSignal<number>(0);
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<button type="button" title={n().toString()} style={dsheet.box} onPress={() => setN(n() + 1)}>go</button>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><button type=\"button\" title=\"0\">go</button></root>", "initial: " + mockToString(directRoot);
	const dBtn = (directRoot as MockNode).children[0];
	fireEvent(dBtn, "onPress");
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

	const directRoot = mockNode("root");
	const mount = element(<div id="top"><section class={cls()}><ul><li>{v()}</li><li><button onPress={bump} title={cls()}>go {v()}</button></li></ul><p>tail</p></section></div>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><div id=\"top\"><section class=\"a\"><ul><li>t</li><li><button title=\"a\">go t</button></li></ul><p>tail</p></section></div></root>", "initial: " + mockToString(directRoot);
	setCls("b");
	assert mockToString(directRoot) === "<root><div id=\"top\"><section class=\"b\"><ul><li>t</li><li><button title=\"b\">go t</button></li></ul><p>tail</p></section></div></root>", "after setCls: " + mockToString(directRoot);
	setV("u");
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
		createText: h.createText, setText: h.setText, setAttr: h.setAttr, removeAttr: h.removeAttr,
		setStyle: h.setStyle, setStyleProp: h.setStyleProp, setStyleClass: h.setStyleClass, addEvent: h.addEvent, append: h.append,
		insertBefore: h.insertBefore, removeChild: h.removeChild,
		nextSibling: h.nextSibling, firstChild: h.firstChild, cloneNode: h.cloneNode, voidArea: h.voidArea,
	};
}

test "template mode: a pure subtree is built once and cloned per mount" {
	const [v, setV] = createSignal("a");
	const counter: number[] = [0];
	const host = countingHost(counter);

	const mount = element(<div class="box"><span>s</span><em>{v()}</em></div>);
	assert counter[0] === 0, "no work before the first mount, got " + counter[0].toString();

	const root = mockNode("root");
	mount(host, root as unknown as HostNode, null);
	const afterFirst = counter[0];
	assert afterFirst === 3, "template built once: div+span+em = 3 createElement, got " + afterFirst.toString();

	mount(host, root as unknown as HostNode, null);
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
		setAttr: h.setAttr, removeAttr: h.removeAttr, setStyle: h.setStyle, setStyleProp: h.setStyleProp, setStyleClass: h.setStyleClass, addEvent: h.addEvent,
		append: h.append, insertBefore: h.insertBefore, removeChild: h.removeChild,
		nextSibling: h.nextSibling, firstChild: h.firstChild, cloneNode: h.cloneNode, voidArea: h.voidArea,
	};
}

test "a spot recomputing to the same string writes the host once" {
	const [n, setN] = createSignal<number>(1);
	const counter: number[] = [0];
	const host = textCountingHost(counter);
	const root = mockNode("root");

	const mount = element(<p>{n() > 5 ? "big" : "small"}</p>);
	mount(host, root as unknown as HostNode, null);
	assert counter[0] === 1, "one write at mount, got " + counter[0].toString();

	setN(2);
	assert counter[0] === 1, "source changed but the derived text did not — no host touch; got " + counter[0].toString();

	setN(9);
	assert counter[0] === 2, "a real change still writes, got " + counter[0].toString();
	assert mockToString(root) === "<root><p>big</p></root>", "value: " + mockToString(root);
}

test "a spot with no call and no property access renders as written" {
	const label = "hi";
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<p class={label}>{label}</p>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><p class=\"hi\">hi</p></root>", "value: " + mockToString(directRoot);
}

test "template mode on a cloneNode:null host falls back and renders the same" {
	const [v, setV] = createSignal("a");
	const base = mockHost();
	const host: Host = {
		createElement: base.createElement, createText: base.createText, setText: base.setText,
		setAttr: base.setAttr, removeAttr: base.removeAttr, setStyle: base.setStyle, setStyleProp: base.setStyleProp, setStyleClass: base.setStyleClass, addEvent: base.addEvent,
		append: base.append, insertBefore: base.insertBefore, removeChild: base.removeChild,
		nextSibling: base.nextSibling, firstChild: base.firstChild,
		cloneNode: null,
		voidArea: null,
	};

	const directRoot = mockNode("root");
	const mount = element(<ul class="l"><li>{v()}</li><li>x</li></ul>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><ul class=\"l\"><li>a</li><li>x</li></ul></root>", "fallback initial: " + mockToString(directRoot);
	setV("z");
	assert mockToString(directRoot) === "<root><ul class=\"l\"><li>z</li><li>x</li></ul></root>", "golden: " + mockToString(directRoot);
}

test "For reorder" {
	const [items, setItems] = createSignal<number[]>([1, 2, 3]);
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<ul><For each={items()}>{(item: number, i: () => number): NeonNode => element(<li>{item.toString()}</li>)}</For></ul>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><ul><li>1</li><li>2</li><li>3</li></ul></root>", "initial: " + mockToString(directRoot);
	setItems([3, 1, 2]);
	assert mockToString(directRoot) === "<root><ul><li>3</li><li>1</li><li>2</li></ul></root>", "golden after reorder: " + mockToString(directRoot);
	setItems([3, 1, 2, 4]);
	assert mockToString(directRoot) === "<root><ul><li>3</li><li>1</li><li>2</li><li>4</li></ul></root>", "after append: " + mockToString(directRoot);
	setItems([2]);
	assert mockToString(directRoot) === "<root><ul><li>2</li></ul></root>", "golden after shrink: " + mockToString(directRoot);
}

test "a && <X/>" {
	const [on, setOn] = createSignal(true);
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = element(<div><p>a</p>{on && <span>yes</span>}<p>z</p></div>);
	mount(host, directRoot as unknown as HostNode, null);
	assert mockToString(directRoot) === "<root><div><p>a</p><span>yes</span><p>z</p></div></root>", "golden while true: " + mockToString(directRoot);
	setOn(false);
	assert mockToString(directRoot) === "<root><div><p>a</p><p>z</p></div></root>", "golden while false: " + mockToString(directRoot);
	setOn(true);
	assert mockToString(directRoot) === "<root><div><p>a</p><span>yes</span><p>z</p></div></root>", "after on: " + mockToString(directRoot);
}

test "c ? <A/> : <B/>" {
	const [on, setOn] = createSignal(false);
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = element(<div>{on ? <span>yes</span> : <b>no</b>}</div>);
	mount(host, directRoot as unknown as HostNode, null);
	assert mockToString(directRoot) === "<root><div><b>no</b></div></root>", "golden false state: " + mockToString(directRoot);
	setOn(true);
	assert mockToString(directRoot) === "<root><div><span>yes</span></div></root>", "golden true state: " + mockToString(directRoot);
}

test "xs.map(row)" {
	const [items, setItems] = createSignal<number[]>([1, 2, 3]);
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = element(<ul>{items.map((n: number): NeonNode => element(<li>{n.toString()}</li>))}</ul>);
	mount(host, directRoot as unknown as HostNode, null);
	assert mockToString(directRoot) === "<root><ul><li>1</li><li>2</li><li>3</li></ul></root>", "initial: " + mockToString(directRoot);
	setItems([3, 1, 2, 4]);
	assert mockToString(directRoot) === "<root><ul><li>3</li><li>1</li><li>2</li><li>4</li></ul></root>", "golden: " + mockToString(directRoot);
}

interface BareTagProps {
	label: Accessor<string>;
}

function BareTag(props: BareTagProps): NeonNode {
	return element(<b>{props.label}</b>);
}

test "a bare accessor attribute and child" {
	const [l, setL] = createSignal("a");
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = element(<p class={l}>{l}</p>);
	mount(host, directRoot as unknown as HostNode, null);
	setL("b");
	assert mockToString(directRoot) === "<root><p class=\"b\">b</p></root>", "value: " + mockToString(directRoot);
}

test "an accessor operand, a bare child and an accessor prop beside a component" {
	const [l, setL] = createSignal("a");
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = element(<div title={(n * 2).toString()}>{l}<BareTag label={l} /></div>);
	mount(host, directRoot as unknown as HostNode, null);
	setL("b");
	setN(4);
	assert mockToString(directRoot) === "<root><div title=\"8\">b<b>b</b></div></root>", "golden: " + mockToString(directRoot);
}

// ---- D3 flat emission: lowercase siblings beside a component tag ----

test "static attr, static text, event and ref beside a component" {
	const [n, setN] = createSignal<number>(1);
	let directHits = 0;
	let directSeen = "";
	const directBump: (e: NeonEvent) => void = () => { directHits = directHits + 1; };
	const directGrab: (b: HostNode) => void = (b) => { directSeen = mockToString(b as unknown as MockNode); };
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div id="top" class="c"><Gauge count={n()} label="g" /><button type="button" onPress={directBump} ref={directGrab}>go</button><p>tail</p></div>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><div id=\"top\" class=\"c\"><p class=\"g\">n=1</p><button type=\"button\">go</button><p>tail</p></div></root>", "golden: " + mockToString(directRoot);
	assert directSeen === "<button type=\"button\">go</button>", "ref saw the finished node: " + directSeen;

	fireEvent((directRoot as MockNode).children[0].children[1], "onPress");
	assert directHits === 1, "one hit: " + directHits.toString();

	setN(5);
	assert mockToString(directRoot) === "<root><div id=\"top\" class=\"c\"><p class=\"g\">n=5</p><button type=\"button\">go</button><p>tail</p></div></root>", "golden after set: " + mockToString(directRoot);
}

test "onChangeText beside a component hands the handler the text" {
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();

	const directRoot = mockNode("root");
	let directText = "";
	const mount = element(<div><Gauge count={n()} label="g" /><input onChangeText={(t: string): void => { directText = t; }} /></div>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><div><p class=\"g\">n=1</p><input></input></div></root>", "golden: " + mockToString(directRoot);

	const e = neonEvent("changetext");
	e.value = "xin chao";
	fireEventWith((directRoot as MockNode).children[0].children[1], "onChangeText", e);
	assert directText === "xin chao", "direct read text=" + directText;
}

test "a ternary with a null arm, either way round" {
	const [on, setOn] = createSignal(true);
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div>{on ? <span>yes</span> : null}<p>m</p>{on ? null : <b>no</b>}</div>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><div><span>yes</span><p>m</p></div></root>", "golden while true: " + mockToString(directRoot);
	setOn(false);
	assert mockToString(directRoot) === "<root><div><p>m</p><b>no</b></div></root>", "golden while false: " + mockToString(directRoot);
	setOn(true);
	assert mockToString(directRoot) === "<root><div><span>yes</span><p>m</p></div></root>", "golden back on: " + mockToString(directRoot);
}

// ---- S13: a whole-style expression that reads a signal is one effect ----

function cssAt(root: MockNode, i: number): string {
	const st = root.children[i].style;
	return st === null ? "(none)" : styleToCss(st as Style);
}

test "a whole-style call tracks the signal — template tier" {
	const [pad, setPad] = createSignal<number>(10);
	const s = (): Style => { const st: Style = { padding: pad() }; return st; };
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div style={s()}><p>a</p></div>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><div><p>a</p></div></root>", "markup: " + mockToString(directRoot);
	assert cssAt(directRoot, 0) === "padding:10px;", "golden: " + cssAt(directRoot, 0);
	setPad(20);
	assert cssAt(directRoot, 0) === "padding:20px;", "golden after set: " + cssAt(directRoot, 0);
}

test "a whole-style call tracks the signal — flat tier" {
	const [pad, setPad] = createSignal<number>(10);
	const [n, setN] = createSignal<number>(1);
	const s = (): Style => { const st: Style = { padding: pad() }; return st; };
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div style={s()}><Gauge count={n()} label="g" /></div>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><div><p class=\"g\">n=1</p></div></root>", "markup: " + mockToString(directRoot);
	assert cssAt(directRoot, 0) === "padding:10px;", "golden: " + cssAt(directRoot, 0);
	setPad(20);
	assert cssAt(directRoot, 0) === "padding:20px;", "golden after set: " + cssAt(directRoot, 0);
}

test "an accessor-typed style and a ternary style track the signal" {
	const [pad, setPad] = createSignal<number>(10);
	const [n, setN] = createSignal<number>(1);
	const memoStyle = createMemo((): Style => { const st: Style = { padding: pad() }; return st; });
	const small: Style = { margin: 1 };
	const big: Style = { margin: 2 };
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div><p style={memoStyle}>a</p><p style={pad() > 15 ? big : small}>b</p><Gauge count={n()} label="g" /></div>);
	mount(host, directRoot as unknown as HostNode, null);

	const dDiv = (directRoot as MockNode).children[0];
	assert mockToString(directRoot) === "<root><div><p>a</p><p>b</p><p class=\"g\">n=1</p></div></root>", "markup: " + mockToString(directRoot);
	assert cssAt(dDiv, 0) === "padding:10px;" && cssAt(dDiv, 1) === "margin:1px;", "golden: " + cssAt(dDiv, 0) + " " + cssAt(dDiv, 1);
	setPad(20);
	assert cssAt(dDiv, 0) === "padding:20px;", "accessor style after set: " + cssAt(dDiv, 0);
	assert cssAt(dDiv, 1) === "margin:2px;", "ternary style after set: " + cssAt(dDiv, 1);
	assert cssAt(dDiv, 0) === "padding:20px;" && cssAt(dDiv, 1) === "margin:2px;", "golden after set: " + cssAt(dDiv, 0) + " " + cssAt(dDiv, 1);
}

// ---- Lát 0.2: a reactive style FIELD is one per-property effect ----

test "reactive style fields track their signals — template tier" {
	const [w, setW] = createSignal<number>(10);
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div style={{ padding: w(), height: n() * 10, margin: 4 }}><p>a</p></div>);
	mount(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><div><p>a</p></div></root>", "markup: " + mockToString(directRoot);
	assert cssAt(directRoot, 0) === "height:10px;margin:4px;padding:10px;", "golden: " + cssAt(directRoot, 0);
	setW(20);
	assert cssAt(directRoot, 0) === "height:10px;margin:4px;padding:20px;", "after setW: " + cssAt(directRoot, 0);
	setN(3);
	assert cssAt(directRoot, 0) === "height:30px;margin:4px;padding:20px;", "golden after set: " + cssAt(directRoot, 0);
}

test "a ternary style field and a bare accessor field track the signal — flat tier" {
	const [pad, setPad] = createSignal<number>(10);
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div><p style={{ margin: pad() > 15 ? 2 : 1 }}>a</p><p style={{ padding: pad }}>b</p><Gauge count={n()} label="g" /></div>);
	mount(host, directRoot as unknown as HostNode, null);

	const dDiv = (directRoot as MockNode).children[0];
	assert mockToString(directRoot) === "<root><div><p>a</p><p>b</p><p class=\"g\">n=1</p></div></root>", "markup: " + mockToString(directRoot);
	assert cssAt(dDiv, 0) === "margin:1px;" && cssAt(dDiv, 1) === "padding:10px;", "golden: " + cssAt(dDiv, 0) + " " + cssAt(dDiv, 1);
	setPad(20);
	assert cssAt(dDiv, 0) === "margin:2px;", "ternary field after set: " + cssAt(dDiv, 0);
	assert cssAt(dDiv, 1) === "padding:20px;", "bare accessor field after set: " + cssAt(dDiv, 1);
	assert cssAt(dDiv, 0) === "margin:2px;" && cssAt(dDiv, 1) === "padding:20px;", "golden after set: " + cssAt(dDiv, 0) + " " + cssAt(dDiv, 1);
}

test "a bare accessor style field — template tier" {
	const [w, setW] = createSignal<number>(10);
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div style={{ padding: w }}><p>a</p></div>);
	mount(host, directRoot as unknown as HostNode, null);

	assert cssAt(directRoot, 0) === "padding:10px;", "initial: " + cssAt(directRoot, 0);
	setW(20);
	assert cssAt(directRoot, 0) === "padding:20px;", "golden after set: " + cssAt(directRoot, 0);
}

test "an identical signal value on a style field is not re-written to the host" {
	const [w, setW] = createSignal<number>(20);
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = element(<div style={{ width: w() }}><p>a</p></div>);
	mount(host, directRoot as unknown as HostNode, null);
	const div = (directRoot as MockNode).children[0];
	const before = div.style;
	setW(20);
	assert div.style === before, "same value writes nothing";
	assert (div.style as Style).width === 20, "value intact";
}

test "an all-static style object lands as one constant" {
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();

	const directRoot = mockNode("root");
	const mount = element(<div style={{ width: 200, height: 120 }}><p style={{ margin: 3, color: "red" }}>a</p><Gauge count={n()} label="g" /></div>);
	mount(host, directRoot as unknown as HostNode, null);

	const dDiv = (directRoot as MockNode).children[0];
	assert mockToString(directRoot) === "<root><div><p>a</p><p class=\"g\">n=1</p></div></root>", "markup: " + mockToString(directRoot);
	assert cssAt(directRoot, 0) === "width:200px;height:120px;", "outer: " + cssAt(directRoot, 0);
	assert cssAt(dDiv, 0) === "margin:3px;color:red;", "inner: " + cssAt(dDiv, 0);
}

test "an all-static style object — template tier" {
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = element(<div style={{ padding: 5 }}><p>a</p></div>);
	mount(host, directRoot as unknown as HostNode, null);
	assert cssAt(directRoot, 0) === "padding:5px;", "golden: " + cssAt(directRoot, 0);
}

// ---- Lát 0.4: style layer arrays ----

test "all-literal style layers merge at expansion — template tier" {
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = element(<div style={[{ width: 200, height: 120 }, { height: 20 }]}><p>a</p></div>);
	mount(host, directRoot as unknown as HostNode, null);
	assert cssAt(directRoot, 0) === "width:200px;height:20px;", "golden: " + cssAt(directRoot, 0);
}

test "a null field in a later literal layer keeps the earlier value — flat tier" {
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = element(<div style={[{ width: 1, height: 5 }, { height: null }, { width: 3 }]}><Gauge count={n()} label="g" /></div>);
	mount(host, directRoot as unknown as HostNode, null);
	assert mockToString(directRoot) === "<root><div><p class=\"g\">n=1</p></div></root>", "markup: " + mockToString(directRoot);
	assert cssAt(directRoot, 0) === "width:3px;height:5px;", "golden: " + cssAt(directRoot, 0);
}

test "a sheet layer under a literal override goes through layerStyles — template tier" {
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = element(<div style={[layerSheet.box, { height: 20 }]}><p>a</p></div>);
	mount(host, directRoot as unknown as HostNode, null);
	assert cssAt(directRoot, 0) === "width:200px;height:20px;", "golden: " + cssAt(directRoot, 0);
}

test "two sheet layers go through layerStyles — flat tier" {
	const [n, setN] = createSignal<number>(1);
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = element(<div style={[layerSheet.box, layerSheet.row]}><Gauge count={n()} label="g" /></div>);
	mount(host, directRoot as unknown as HostNode, null);
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

test "a static sheet entry takes the class route — template tier" {
	resetCss();
	const host = cssHost();
	const directRoot = mockNode("root");
	const mount = element(<div style={dsheet.box}><p>a</p></div>);
	mount(host, directRoot as unknown as HostNode, null);
	mount(host, directRoot as unknown as HostNode, null);
	const dDiv = (directRoot as MockNode).children[0];
	const dDiv2 = (directRoot as MockNode).children[1];
	when (js) {
		assert dDiv.className === (dsheet.box.cssId as string), "golden class: " + dDiv.className;
		assert dDiv2.className === dDiv.className, "second instance carries the same class: " + dDiv2.className;
		assert dDiv.style === null, "no inline style once a class applies";
		assert cssRuleCount() === 1, "one rule shared by both instances, got " + cssRuleCount().toString();
	} else {
		assert dDiv.className === "", "no class off the browser lane";
		assert cssAt(directRoot, 0) === "width:40px;height:10px;", "golden native inline: " + cssAt(directRoot, 0);
		assert cssAt(directRoot, 1) === "width:40px;height:10px;", "second instance: " + cssAt(directRoot, 1);
	}
}

test "a static sheet entry takes the class route — flat tier" {
	resetCss();
	const [n, setN] = createSignal<number>(1);
	const host = cssHost();
	const directRoot = mockNode("root");
	const mount = element(<div style={dsheet.box}><Gauge count={n()} label="g" /></div>);
	mount(host, directRoot as unknown as HostNode, null);
	const dDiv = (directRoot as MockNode).children[0];
	assert mockToString(directRoot) === "<root><div><p class=\"g\">n=1</p></div></root>", "markup: " + mockToString(directRoot);
	when (js) {
		assert dDiv.className === (dsheet.box.cssId as string), "golden class: " + dDiv.className;
		assert dDiv.style === null, "no inline style once a class applies";
	} else {
		assert cssAt(directRoot, 0) === "width:40px;height:10px;", "golden native inline: " + cssAt(directRoot, 0);
	}
}

// ---- Lát 0.6: a static {node} child mounts as a node ----

test "a static node child mounts in place" {
	const host = mockHost();
	const kid: NeonNode = element(<b>k</b>);
	const directRoot = mockNode("root");
	const kid2: NeonNode = element(<b>k</b>);
	const mount = element(<div><p>a</p>{kid2}<p>z</p></div>);
	mount(host, directRoot as unknown as HostNode, null);
	assert mockToString(directRoot) === "<root><div><p>a</p><b>k</b><p>z</p></div></root>", "golden: " + mockToString(directRoot);
}

interface FrameProps {
	title: string;
	children: NeonNode;
}

function Frame(props: FrameProps): NeonNode {
	return element(<section title={props.title}>{props.children}</section>);
}

test "{props.children} carrying a node with live text tracks the signal" {
	const [name, setName] = createSignal("an");
	const host = mockHost();
	const directRoot = mockNode("root");
	const view = Frame({ title: "t", children: element(<p>hi {name()}</p>) });
	view(host, directRoot as unknown as HostNode, null);
	assert mockToString(directRoot) === "<root><section title=\"t\"><p>hi an</p></section></root>", "golden: " + mockToString(directRoot);
	setName("binh");
	assert mockToString(directRoot) === "<root><section title=\"t\"><p>hi binh</p></section></root>", "golden after set: " + mockToString(directRoot);
}

// ---- Lát 0.8: a reactive layer is rejected; the escape hatch is a whole-style layerStyles call ----

test "layerStyles over a reactive layer as a whole-style expression tracks the signal" {
	const [h, setH] = createSignal<number>(5);
	const pick = (): Style => { const s: Style = { height: h() }; return s; };
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = element(<div style={layerStyles([layerSheet.box, pick()])}><p>a</p></div>);
	mount(host, directRoot as unknown as HostNode, null);
	assert cssAt(directRoot, 0) === "width:200px;height:5px;", "golden: " + cssAt(directRoot, 0);
	setH(9);
	assert cssAt(directRoot, 0) === "width:200px;height:9px;", "golden after set: " + cssAt(directRoot, 0);
}

// ---- Lát 0.9: whitespace-only text around a single child does not change the wrapping ----

interface ViewProps {
	children: NeonNode;
}

function View(props: ViewProps): NeonNode {
	return el("view", [], [], props.children);
}

test "whitespace around a primitive's single element child lowers like the flat form" {
	const host = mockHost();
	const flatRoot = mockNode("root");
	const flat: NeonNode = element(<div><View><p>a</p></View></div>);
	render(flat, host, flatRoot as unknown as HostNode);
	const wsRoot = mockNode("root");
	const mount = element(<div><View>
		<p>a</p>
	</View></div>);
	mount(host, wsRoot as unknown as HostNode, null);
	assert mockToString(wsRoot) === mockToString(flatRoot), "ws=" + mockToString(wsRoot) + " flat=" + mockToString(flatRoot);
	assert mockToString(wsRoot) === "<root><div><view><p>a</p></view></div></root>", "golden: " + mockToString(wsRoot);
}

test "whitespace around a primitive's single expression child stays reactive text like the flat form" {
	const [n, setN] = createSignal("v");
	const host = mockHost();
	const flatRoot = mockNode("root");
	const flat: NeonNode = element(<div><View>{n()}</View></div>);
	render(flat, host, flatRoot as unknown as HostNode);
	const wsRoot = mockNode("root");
	const mount = element(<div><View>
		{n()}
	</View></div>);
	mount(host, wsRoot as unknown as HostNode, null);
	assert mockToString(wsRoot) === mockToString(flatRoot), "ws=" + mockToString(wsRoot) + " flat=" + mockToString(flatRoot);
	assert mockToString(wsRoot) === "<root><div><view>v</view></div></root>", "golden: " + mockToString(wsRoot);
	setN("w");
	assert mockToString(wsRoot) === mockToString(flatRoot), "after set: ws=" + mockToString(wsRoot) + " flat=" + mockToString(flatRoot);
	assert mockToString(wsRoot) === "<root><div><view>w</view></div></root>", "golden after set: " + mockToString(wsRoot);
}

test "whitespace around a user component's single element child lowers like the flat form" {
	const host = mockHost();
	const flatRoot = mockNode("root");
	const flat: NeonNode = element(<div><Card title="t"><p>a</p></Card></div>);
	render(flat, host, flatRoot as unknown as HostNode);
	const wsRoot = mockNode("root");
	const mount = element(<div><Card title="t">
		<p>a</p>
	</Card></div>);
	mount(host, wsRoot as unknown as HostNode, null);
	assert mockToString(wsRoot) === mockToString(flatRoot), "ws=" + mockToString(wsRoot) + " flat=" + mockToString(flatRoot);
	assert mockToString(wsRoot) === "<root><div><section title=\"t\"><p>a</p></section></div></root>", "golden: " + mockToString(wsRoot);
}

test "a static string expression as a component's only child mounts as text" {
	const label: string = "hi";
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = element(<div><Card title="t">{label}</Card></div>);
	mount(host, directRoot as unknown as HostNode, null);
	assert mockToString(directRoot) === "<root><div><section title=\"t\">hi</section></div></root>", "golden: " + mockToString(directRoot);
}

// ---- Lát 0.11: a nullable-typed on*/ref/style attaches only when the value is present ----

function optTemplate(h: ((e: NeonEvent) => void) | null, r: ((b: HostNode) => void) | null, s: Style | null, a: Accessor<Style> | null): NeonNode {
	return element(<div><button type="button" onPress={h} ref={r} style={s}>go</button><p style={a}>x</p></div>);
}

function optFlat(h: ((e: NeonEvent) => void) | null, r: ((b: HostNode) => void) | null, s: Style | null, a: Accessor<Style> | null): NeonNode {
	return element(<div><Gauge count={1} label="g" /><button type="button" onPress={h} ref={r} style={s}>go</button><p style={a}>x</p></div>);
}

test "null on*/ref/style attach nothing — template tier" {
	const host = mockHost();
	const directRoot = mockNode("root");
	optTemplate(null, null, null, null)(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><div><button type=\"button\">go</button><p>x</p></div></root>", "golden: " + mockToString(directRoot);
	const btn = (directRoot as MockNode).children[0].children[0];
	assert btn.events.length === 0, "no listener for a null handler: " + btn.events.length.toString();
	assert cssAt((directRoot as MockNode).children[0], 0) === "(none)", "no style for a null Style: " + cssAt((directRoot as MockNode).children[0], 0);
	assert cssAt((directRoot as MockNode).children[0], 1) === "(none)", "no style for a null accessor: " + cssAt((directRoot as MockNode).children[0], 1);
}

test "present on*/ref/style through a nullable type attach — template tier" {
	const [pad, setPad] = createSignal<number>(3);
	let hits = 0;
	let seen = "";
	const bump: (e: NeonEvent) => void = () => { hits = hits + 1; };
	const grab: (b: HostNode) => void = (b) => { seen = mockToString(b as unknown as MockNode); };
	const fixed: Style = { margin: 2 };
	const live = accessor((): Style => { const st: Style = { padding: pad() }; return st; });
	const host = mockHost();

	const directRoot = mockNode("root");
	optTemplate(bump, grab, fixed, live)(host, directRoot as unknown as HostNode, null);

	const dDiv = (directRoot as MockNode).children[0];
	assert mockToString(directRoot) === "<root><div><button type=\"button\">go</button><p>x</p></div></root>", "golden: " + mockToString(directRoot);
	assert seen === "<button type=\"button\">go</button>", "ref saw the finished node: " + seen;
	fireEvent(dDiv.children[0], "onPress");
	assert hits === 1, "one hit: " + hits.toString();
	assert cssAt(dDiv, 0) === "margin:2px;", "static style: " + cssAt(dDiv, 0);
	assert cssAt(dDiv, 1) === "padding:3px;", "accessor style: " + cssAt(dDiv, 1);
	setPad(8);
	assert cssAt(dDiv, 1) === "padding:8px;", "accessor style after set: " + cssAt(dDiv, 1);
}

test "null on*/ref/style attach nothing — flat tier" {
	const host = mockHost();
	const directRoot = mockNode("root");
	optFlat(null, null, null, null)(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><div><p class=\"g\">n=1</p><button type=\"button\">go</button><p>x</p></div></root>", "golden: " + mockToString(directRoot);
	const dDiv = (directRoot as MockNode).children[0];
	assert dDiv.children[1].events.length === 0, "no listener for a null handler: " + dDiv.children[1].events.length.toString();
	assert cssAt(dDiv, 1) === "(none)" && cssAt(dDiv, 2) === "(none)", "no style: " + cssAt(dDiv, 1) + " / " + cssAt(dDiv, 2);
}

test "present on*/ref/style through a nullable type attach — flat tier" {
	const [pad, setPad] = createSignal<number>(3);
	let hits = 0;
	let seen = "";
	const bump: (e: NeonEvent) => void = () => { hits = hits + 1; };
	const grab: (b: HostNode) => void = (b) => { seen = mockToString(b as unknown as MockNode); };
	const fixed: Style = { margin: 2 };
	const live = accessor((): Style => { const st: Style = { padding: pad() }; return st; });
	const host = mockHost();

	const directRoot = mockNode("root");
	optFlat(bump, grab, fixed, live)(host, directRoot as unknown as HostNode, null);

	const dDiv = (directRoot as MockNode).children[0];
	assert mockToString(directRoot) === "<root><div><p class=\"g\">n=1</p><button type=\"button\">go</button><p>x</p></div></root>", "golden: " + mockToString(directRoot);
	assert seen === "<button type=\"button\">go</button>", "ref saw the finished node: " + seen;
	fireEvent(dDiv.children[1], "onPress");
	assert hits === 1, "one hit: " + hits.toString();
	assert cssAt(dDiv, 1) === "margin:2px;", "static style: " + cssAt(dDiv, 1);
	assert cssAt(dDiv, 2) === "padding:3px;", "accessor style: " + cssAt(dDiv, 2);
	setPad(8);
	assert cssAt(dDiv, 2) === "padding:8px;", "accessor style after set: " + cssAt(dDiv, 2);
}

function Tag(props: { children: NeonNode }): NeonNode {
	return <b>{props.children}</b>;
}

test "a numeric child renders as text and follows its signal — template tier" {
	const [n, setN] = createSignal(7);
	const [f, setF] = createSignal<number>(1.5);
	const k: number = 3;
	const host = mockHost();
	const root = mockNode("root");
	const mount = element(<p>{n}|{n()}|{n() + 1}|{k}|{f}</p>);
	mount(host, root as unknown as HostNode, null);
	assert mockToString(root) === "<root><p>7|7|8|3|1.5</p></root>", "initial: " + mockToString(root);
	setN(8);
	setF(2.25);
	assert mockToString(root) === "<root><p>8|8|9|3|2.25</p></root>", "after set: " + mockToString(root);
}

test "a numeric child renders as text and follows its signal — flat tier" {
	const [n, setN] = createSignal(7);
	const k: number = 3;
	const host = mockHost();
	const root = mockNode("root");
	const mount = element(<p>{n}|{n() + 1}|{k}<Tag>{n}</Tag></p>);
	mount(host, root as unknown as HostNode, null);
	assert mockToString(root) === "<root><p>7|8|3<b>7</b></p></root>", "initial: " + mockToString(root);
	setN(8);
	assert mockToString(root) === "<root><p>8|9|3<b>8</b></p></root>", "after set: " + mockToString(root);
}

// ---- on* is an event only as `on` + an uppercase letter, on a tag and on a component alike ----

interface NetProps {
	online: Accessor<string>;
}

function Net(props: NetProps): NeonNode {
	return element(<i>{props.online()}</i>);
}

test "once and online are attributes, not events — template tier" {
	const [v, setV] = createSignal("y");
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = element(<p once="x" online={v()}>hi</p>);
	mount(host, directRoot as unknown as HostNode, null);
	assert mockToString(directRoot) === "<root><p once=\"x\" online=\"y\">hi</p></root>", "golden: " + mockToString(directRoot);
	assert (directRoot as MockNode).children[0].events.length === 0, "no listener";
	setV("z");
	assert mockToString(directRoot) === "<root><p once=\"x\" online=\"z\">hi</p></root>", "golden after set: " + mockToString(directRoot);
}

test "once and online are attributes, not events — flat tier" {
	const [v, setV] = createSignal("y");
	const host = mockHost();
	const directRoot = mockNode("root");
	const mount = element(<div><Net online={v()} /><p once="x" online={v()}>hi</p></div>);
	mount(host, directRoot as unknown as HostNode, null);
	assert mockToString(directRoot) === "<root><div><i>y</i><p once=\"x\" online=\"y\">hi</p></div></root>", "golden: " + mockToString(directRoot);
	assert (directRoot as MockNode).children[0].children[1].events.length === 0, "no listener";
	setV("z");
	assert mockToString(directRoot) === "<root><div><i>z</i><p once=\"x\" online=\"z\">hi</p></div></root>", "golden after set: " + mockToString(directRoot);
}

// ---- a nullable Accessor attribute and a nullable NeonNode child attach only when present ----

function optAttrTemplate(c: Accessor<string> | null): NeonNode {
	return element(<div><p class={c}>x</p></div>);
}

function optAttrFlat(c: Accessor<string> | null): NeonNode {
	return element(<div><Gauge count={1} label="g" /><p class={c}>x</p></div>);
}

function optChild(k: NeonNode | null): NeonNode {
	return element(<div><p>a</p>{k}<p>z</p></div>);
}

test "a nullable Accessor attribute binds when present and leaves nothing when null — template tier" {
	const [cls, setCls] = createSignal("a");
	const host = mockHost();
	const directRoot = mockNode("root");
	optAttrTemplate(cls)(host, directRoot as unknown as HostNode, null);
	optAttrTemplate(null)(host, directRoot as unknown as HostNode, null);
	assert mockToString(directRoot) === "<root><div><p class=\"a\">x</p></div><div><p>x</p></div></root>", "golden: " + mockToString(directRoot);
	setCls("b");
	assert mockToString(directRoot) === "<root><div><p class=\"b\">x</p></div><div><p>x</p></div></root>", "golden after set: " + mockToString(directRoot);
}

test "a nullable Accessor attribute binds when present and leaves nothing when null — flat tier" {
	const [cls, setCls] = createSignal("a");
	const host = mockHost();
	const directRoot = mockNode("root");
	optAttrFlat(cls)(host, directRoot as unknown as HostNode, null);
	optAttrFlat(null)(host, directRoot as unknown as HostNode, null);
	assert mockToString(directRoot) === "<root><div><p class=\"g\">n=1</p><p class=\"a\">x</p></div><div><p class=\"g\">n=1</p><p>x</p></div></root>", "golden: " + mockToString(directRoot);
	setCls("b");
	assert mockToString(directRoot) === "<root><div><p class=\"g\">n=1</p><p class=\"b\">x</p></div><div><p class=\"g\">n=1</p><p>x</p></div></root>", "golden after set: " + mockToString(directRoot);
}

test "a nullable NeonNode child mounts in place when present and mounts nothing when null" {
	const host = mockHost();
	const directRoot = mockNode("root");
	optChild(element(<b>k</b>))(host, directRoot as unknown as HostNode, null);
	optChild(null)(host, directRoot as unknown as HostNode, null);
	assert mockToString(directRoot) === "<root><div><p>a</p><b>k</b><p>z</p></div><div><p>a</p><p>z</p></div></root>", "golden: " + mockToString(directRoot);
}

// ---- the same nullable spots written as bare JSX, lowered by the converter ----

function optBare(h: ((e: NeonEvent) => void) | null, r: ((b: HostNode) => void) | null, s: Style | null, a: Accessor<Style> | null): NeonNode {
	return <div><button type="button" onPress={h} ref={r} style={s}>go</button><p style={a}>x</p></div>;
}

function optAttrBare(c: Accessor<string> | null): NeonNode {
	return <div><p class={c}>x</p></div>;
}

function optChildBare(k: NeonNode | null): NeonNode {
	return <div><p>a</p>{k}<p>z</p></div>;
}

test "null on*/ref/style attach nothing — bare JSX" {
	const host = mockHost();
	const directRoot = mockNode("root");
	optBare(null, null, null, null)(host, directRoot as unknown as HostNode, null);

	assert mockToString(directRoot) === "<root><div><button type=\"button\">go</button><p>x</p></div></root>", "golden: " + mockToString(directRoot);
	const btn = (directRoot as MockNode).children[0].children[0];
	assert btn.events.length === 0, "no listener for a null handler: " + btn.events.length.toString();
	assert cssAt((directRoot as MockNode).children[0], 0) === "(none)", "no style for a null Style: " + cssAt((directRoot as MockNode).children[0], 0);
	assert cssAt((directRoot as MockNode).children[0], 1) === "(none)", "no style for a null accessor: " + cssAt((directRoot as MockNode).children[0], 1);
}

test "present on*/ref/style through a nullable type attach — bare JSX" {
	const [pad, setPad] = createSignal<number>(3);
	let hits = 0;
	let seen = "";
	const bump: (e: NeonEvent) => void = () => { hits = hits + 1; };
	const grab: (b: HostNode) => void = (b) => { seen = mockToString(b as unknown as MockNode); };
	const fixed: Style = { margin: 2 };
	const live = accessor((): Style => { const st: Style = { padding: pad() }; return st; });
	const host = mockHost();

	const directRoot = mockNode("root");
	optBare(bump, grab, fixed, live)(host, directRoot as unknown as HostNode, null);

	const dDiv = (directRoot as MockNode).children[0];
	assert seen === "<button type=\"button\">go</button>", "ref saw the finished node: " + seen;
	fireEvent(dDiv.children[0], "onPress");
	assert hits === 1, "one hit: " + hits.toString();
	assert cssAt(dDiv, 0) === "margin:2px;", "static style: " + cssAt(dDiv, 0);
	assert cssAt(dDiv, 1) === "padding:3px;", "accessor style: " + cssAt(dDiv, 1);
	setPad(8);
	assert cssAt(dDiv, 1) === "padding:8px;", "accessor style after set: " + cssAt(dDiv, 1);
}

test "a nullable Accessor attribute binds when present and leaves nothing when null — bare JSX" {
	const [cls, setCls] = createSignal("a");
	const host = mockHost();
	const directRoot = mockNode("root");
	optAttrBare(cls)(host, directRoot as unknown as HostNode, null);
	optAttrBare(null)(host, directRoot as unknown as HostNode, null);
	assert mockToString(directRoot) === "<root><div><p class=\"a\">x</p></div><div><p>x</p></div></root>", "golden: " + mockToString(directRoot);
	setCls("b");
	assert mockToString(directRoot) === "<root><div><p class=\"b\">x</p></div><div><p>x</p></div></root>", "golden after set: " + mockToString(directRoot);
}

test "a nullable NeonNode child mounts in place when present and mounts nothing when null — bare JSX" {
	const host = mockHost();
	const directRoot = mockNode("root");
	optChildBare(<b>k</b>)(host, directRoot as unknown as HostNode, null);
	optChildBare(null)(host, directRoot as unknown as HostNode, null);
	assert mockToString(directRoot) === "<root><div><p>a</p><b>k</b><p>z</p></div><div><p>a</p><p>z</p></div></root>", "golden: " + mockToString(directRoot);
}
