import { createSignal, accessor, Accessor } from "../../src/core/signal";
import { el, text, NeonNode } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { createComponent } from "../../src/render/component";
import { createContext, useContext } from "../../src/render/context";
import { For, Index, Show } from "../../src/macros/ui/flow";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { Style } from "../../src/render/style";
import { collectCss, resetCss } from "../../src/render/sheet";

const sheet = createStyles({
	box: { padding: 8, backgroundColor: "#334" },
});

function boxOf(): Style { return sheet.box; }

const BOX_CSS = "padding:8px;background-color:#334;";

test "plain markup serializes as written" {
	assert renderToString(<div></div>) === "<div></div>", "empty element: " + renderToString(<div></div>);
	assert renderToString(<div class="box">hi</div>) === "<div class=\"box\">hi</div>", "attr + text";
	assert renderToString(<ul><li>a</li><li>b</li></ul>) === "<ul><li>a</li><li>b</li></ul>", "nested";
	assert renderToString(<view><text>x</text></view>) === "<div><span>x</span></div>", "wire tags become html tags";
	assert renderToString(text("bare text")) === "bare text", "a bare text root";
	const order = renderToString(<input value="v" id="i" />);
	assert order === "<input value=\"v\" id=\"i\"></input>", "attribute order: " + order;
}

test "reactive text and attributes serialize their current value" {
	const [n, _setN] = createSignal(7);
	const [cls, _setCls] = createSignal("on");
	assert renderToString(<p>{n().toString()}</p>) === "<p>7</p>", "dyn text";
	assert renderToString(<p class={cls()}>hi</p>) === "<p class=\"on\">hi</p>", "dyn attr";
	const both = renderToString(<p class={cls()}>{n().toString()}</p>);
	assert both === "<p class=\"on\">7</p>", "both: " + both;
}

test "a style serializes inline, or as a sheet class where the entry carries one" {
	const id = sheet.box.cssId;
	const entry = renderToString(<div style={sheet.box}></div>);
	const beside = renderToString(<div class="outer" style={sheet.box}></div>);
	if (id !== null) {
		assert entry === "<div class=\"" + (id as string) + "\"></div>", "sheet entry: " + entry;
		assert beside === "<div class=\"outer " + (id as string) + "\"></div>", "sheet entry beside a class attr: " + beside;
	} else {
		assert entry === "<div style=\"" + BOX_CSS + "\"></div>", "sheet entry: " + entry;
		assert beside === "<div class=\"outer\" style=\"" + BOX_CSS + "\"></div>", "sheet entry beside a class attr: " + beside;
	}
	const whole = renderToString(<div style={boxOf()}></div>);
	assert whole === "<div style=\"" + BOX_CSS + "\"></div>", "whole-style thunk: " + whole;
}

test "a render registers the rule of the sheet entry it used" {
	when (js) {
		resetCss();
		renderToString(<div style={sheet.box}></div>);
		const css = collectCss();
		assert css === "." + (sheet.box.cssId as string) + "{" + BOX_CSS + "}", "css: " + css;
	}
}

interface Skin { accent: string; }

interface LabelProps {
	label: Accessor<string>;
}

function Label(props: LabelProps): NeonNode {
	return <span>{props.label()}</span>;
}

test "components and context scopes serialize through" {
	const child = renderToString(<div><Label label="hi" /></div>);
	assert child === "<div><span>hi</span></div>", "component child: " + child;
	const root = renderToString(<Label label="root" />);
	assert root === "<span>root</span>", "component root: " + root;

	const T = createContext<Skin>({ accent: "light" });
	const scoped = renderToString(
		<T.Provider value={{ accent: "dark" }}>
			<div>{useContext(T).accent}</div>
		</T.Provider>
	);
	assert scoped === "<div>dark</div>", "provider scope: " + scoped;
}

test "fragments serialize every root in order" {
	const frag = renderToString(<><i>a</i><b>b</b></>);
	assert frag === "<i>a</i><b>b</b>", "fragment root: " + frag;
	const none = renderToString(<></>);
	assert none === "", "empty fragment root: " + none;
	const kid = renderToString(<div><>{"a"}{"b"}</></div>);
	assert kid === "<div>ab</div>", "fragment child: " + kid;
}

test "regions serialize their current rows" {
	const [items, _setItems] = createSignal<number[]>([1, 2]);
	const rows = el("ul", [], [], For<number>({ each: () => items(), children: (item, i) => <li>{"" + item}</li> }));
	assert renderToString(rows) === "<ul><li>1</li><li>2</li></ul>", "For: " + renderToString(rows);

	const indexed = el("ul", [], [], Index<number>({ each: () => items(), children: (item, i) => <li>{item().toString()}</li> }));
	assert renderToString(indexed) === "<ul><li>1</li><li>2</li></ul>", "Index: " + renderToString(indexed);

	const [on, _setOn] = createSignal(true);
	const shown = el("div", [], [], Show({ when: () => on(), children: <span>yes</span>, fallback: <b>no</b> }));
	assert renderToString(shown) === "<div><span>yes</span></div>", "Show: " + renderToString(shown);
}

test "an empty list serializes through its fallback" {
	const [items, _setItems] = createSignal<number[]>([]);
	const rows = el("ul", [], [], For<number>({
		each: () => items(),
		children: (item, i) => <li>{"" + item}</li>,
		fallback: <li>empty</li>,
	}));
	assert renderToString(rows) === "<ul><li>empty</li></ul>", "fallback: " + renderToString(rows);
}

test "a region at the root of the render renders too" {
	const [items, _setItems] = createSignal<number[]>([1, 2, 3]);
	const rows = For<number>({ each: () => items(), children: (item, i) => <i>{"" + item}</i> });
	assert renderToString(rows) === "<i>1</i><i>2</i><i>3</i>", "root region: " + renderToString(rows);
}

test "the shared SSR host carries nothing over between renders" {
	const [items, setItems] = createSignal<number[]>([1]);
	const rows = el("ul", [], [], For<number>({ each: () => items(), children: (item, i) => <li>{"" + item}</li> }));
	const first = renderToString(rows);
	const second = renderToString(rows);
	assert first === second, "same tree twice: first=" + first + " second=" + second;
	setItems([1, 2]);
	const third = renderToString(rows);
	assert third === "<ul><li>1</li><li>2</li></ul>", "a later render sees the current signal: " + third;
	const plain = renderToString(<div>x</div>);
	assert plain === "<div>x</div>", "an unrelated render is not polluted: " + plain;
}
