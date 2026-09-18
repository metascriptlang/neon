import { createSignal, accessor, Accessor } from "../../src/core/signal";
import { el, attr, dynAttr, text, dynText, withStyle, withDynStyleAll, fragmentNode, NeonNode, renderToString } from "../../src/render/node";
import { renderToStringViaHost } from "../../src/render/ssr";
import { createComponent } from "../../src/render/component";
import { createContext, useContext } from "../../src/render/context";
import { For, Index, Show } from "../../src/macros/ui/flow";
import { viewOf } from "../../src/render/host";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { Style } from "../../src/render/style";
import { collectCss, resetCss } from "../../src/render/sheet";

const sheet = createStyles({
	box: { padding: 8, backgroundColor: "#334" },
});

function boxOf(): Style { return sheet.box; }

function diff(n: NeonNode): string {
	const viaWalk = renderToString(n);
	const viaHost = renderToStringViaHost(n);
	return viaHost === viaWalk ? "" : "walk=" + viaWalk + " host=" + viaHost;
}

test "the host path agrees with the description walker on plain markup" {
	const empty = diff(<div></div>);
	assert empty === "", "empty element: " + empty;
	const attrText = diff(<div class="box">hi</div>);
	assert attrText === "", "attr + text: " + attrText;
	const nested = diff(<ul><li>a</li><li>b</li></ul>);
	assert nested === "", "nested: " + nested;
	const wire = diff(<view><text>x</text></view>);
	assert wire === "", "wire tags become html tags: " + wire;
	const bare = diff(text("bare text"));
	assert bare === "", "a bare text root: " + bare;
	const order = diff(<input value="v" id="i" />);
	assert order === "", "attribute order: " + order;
}

test "the host path agrees on reactive text and attributes" {
	const [n, _setN] = createSignal(7);
	const [cls, _setCls] = createSignal("on");
	const dt = diff(<p>{n().toString()}</p>);
	assert dt === "", "dyn text: " + dt;
	const da = diff(<p class={cls()}>hi</p>);
	assert da === "", "dyn attr: " + da;
	const both = diff(<p class={cls()}>{n().toString()}</p>);
	assert both === "", "both: " + both;
}

test "the host path agrees on styles, inline and as a sheet class" {
	const entry = diff(<div style={sheet.box}></div>);
	assert entry === "", "sheet entry: " + entry;
	const beside = diff(<div class="outer" style={sheet.box}></div>);
	assert beside === "", "sheet entry beside a class attr: " + beside;
	const whole = diff(<div style={boxOf()}></div>);
	assert whole === "", "whole-style thunk: " + whole;
}

test "the sheet collected by the host path is the sheet the walker collects" {
	when (js) {
		resetCss();
		const walked = renderToString(<div style={sheet.box}></div>);
		const walkCss = collectCss();
		resetCss();
		const hosted = renderToStringViaHost(<div style={sheet.box}></div>);
		const hostCss = collectCss();
		assert hosted === walked, "markup: walk=" + walked + " host=" + hosted;
		assert hostCss === walkCss, "css: walk=" + walkCss + " host=" + hostCss;
		assert walkCss !== "", "the entry produced a rule at all";
	}
}

interface Skin { accent: string; }

interface LabelProps {
	label: Accessor<string>;
}

function Label(props: LabelProps): NeonNode {
	return <span>{props.label()}</span>;
}

test "the host path agrees on components and context scopes" {
	const child = diff(<div><Label label="hi" /></div>);
	assert child === "", "component child: " + child;
	const root = diff(<Label label="root" />);
	assert root === "", "component root: " + root;

	const T = createContext<Skin>({ accent: "light" });
	const scoped = diff(
		<T.Provider value={{ accent: "dark" }}>
			<div>{useContext(T).accent}</div>
		</T.Provider>
	);
	assert scoped === "", "provider scope: " + scoped;
}

test "the host path agrees on fragments, which the walker also renders" {
	const frag = diff(<><i>a</i><b>b</b></>);
	assert frag === "", "fragment root: " + frag;
	const none = diff(<></>);
	assert none === "", "empty fragment root: " + none;
	const kid = diff(<div><>{"a"}{"b"}</></div>);
	assert kid === "", "fragment child: " + kid;
}

test "the host path renders regions the walker refuses" {
	const [items, _setItems] = createSignal<number[]>([1, 2]);
	const rows = el("ul", [], [], [
		For<number>({ each: () => items(), children: (item, i) => viewOf(<li>{"" + item}</li>) }),
	]);
	assert renderToStringViaHost(rows) === "<ul><li>1</li><li>2</li></ul>", "For: " + renderToStringViaHost(rows);

	const indexed = el("ul", [], [], [
		Index<number>({ each: () => items(), children: (item, i) => viewOf(<li>{item().toString()}</li>) }),
	]);
	assert renderToStringViaHost(indexed) === "<ul><li>1</li><li>2</li></ul>", "Index: " + renderToStringViaHost(indexed);

	const [on, _setOn] = createSignal(true);
	const shown = el("div", [], [], [
		Show({ when: () => on(), children: viewOf(<span>yes</span>), fallback: viewOf(<b>no</b>) }),
	]);
	assert renderToStringViaHost(shown) === "<div><span>yes</span></div>", "Show: " + renderToStringViaHost(shown);
}

test "the host path renders an empty list through its fallback" {
	const [items, _setItems] = createSignal<number[]>([]);
	const rows = el("ul", [], [], [
		For<number>({
			each: () => items(),
			children: (item, i) => viewOf(<li>{"" + item}</li>),
			fallback: viewOf(<li>empty</li>),
		}),
	]);
	assert renderToStringViaHost(rows) === "<ul><li>empty</li></ul>", "fallback: " + renderToStringViaHost(rows);
}

test "a region at the root of the render renders too" {
	const [items, _setItems] = createSignal<number[]>([1, 2, 3]);
	const rows = For<number>({ each: () => items(), children: (item, i) => viewOf(<i>{"" + item}</i>) });
	assert renderToStringViaHost(rows) === "<i>1</i><i>2</i><i>3</i>", "root region: " + renderToStringViaHost(rows);
}

test "the shared SSR host carries nothing over between renders" {
	const [items, setItems] = createSignal<number[]>([1]);
	const rows = el("ul", [], [], [
		For<number>({ each: () => items(), children: (item, i) => viewOf(<li>{"" + item}</li>) }),
	]);
	const first = renderToStringViaHost(rows);
	const second = renderToStringViaHost(rows);
	assert first === second, "same tree twice: first=" + first + " second=" + second;
	setItems([1, 2]);
	const third = renderToStringViaHost(rows);
	assert third === "<ul><li>1</li><li>2</li></ul>", "a later render sees the current signal: " + third;
	const plain = renderToStringViaHost(<div>x</div>);
	assert plain === "<div>x</div>", "an unrelated render is not polluted: " + plain;
}
