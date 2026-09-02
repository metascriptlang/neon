import { createSignal } from "../../src/core/signal";
import { el, attr, text, dynText, renderToString } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";

test "reactive element renders and updates on signal change" {
	const [name, setName] = createSignal("world");
	const node = element(<p>Hi {name()}</p>);
	assert renderToString(node) === "<p>Hi world</p>", "initial render";
	setName("neon");
	assert renderToString(node) === "<p>Hi neon</p>", "render updates after set";
}

test "JSX bound to a const is consumed by element()" {
	const [name, setName] = createSignal("world");
	const view = <p>Hi {name()}</p>;
	const node = element(view);
	assert renderToString(node) === "<p>Hi world</p>", "const-form initial render";
	setName("neon");
	assert renderToString(node) === "<p>Hi neon</p>", "const-form updates after set";
}

// JSX whitespace (Babel cleanJSXElementLiteralChild). Every other JSX test in
// this suite is written on ONE line, so multi-line JSX went unexercised until
// the Void host needed it — and both a dropped-text and a not-stripped bug hid
// there. These pin the rule in both axes: newline-bearing whitespace is
// insignificant, same-line whitespace is significant.

test "whitespace-only children between elements are dropped" {
	const node = element(
		<div>
			<p>x</p>
			<b>y</b>
		</div>
	);
	assert renderToString(node) === "<div><p>x</p><b>y</b></div>", "indentation between elements";
}

test "a same-line space between elements is significant and kept" {
	const node = element(<p><b>a</b> <i>c</i></p>);
	assert renderToString(node) === "<p><b>a</b> <i>c</i></p>", "single space has no newline";
}

test "text spanning lines is rejoined with single spaces" {
	const node = element(
		<p>
			hello
			world
		</p>
	);
	assert renderToString(node) === "<p>hello world</p>", "indentation stripped, lines joined";
}

test "text alone on its own line keeps its content" {
	const withAttr = element(
		<p a="1">
			hello
		</p>
	);
	assert renderToString(withAttr) === "<p a=\"1\">hello</p>", "attributed element keeps text";
	const noAttr = element(
		<p>
			hello
		</p>
	);
	assert renderToString(noAttr) === "<p>hello</p>", "unattributed element keeps text";
}

test "single-line text passes through byte for byte" {
	assert renderToString(element(<p>Count: </p>)) === "<p>Count: </p>", "trailing space kept";
	assert renderToString(element(<p>  spaced  </p>)) === "<p>  spaced  </p>", "inner padding kept";
}

test "text around an element on separate lines keeps both runs" {
	const node = element(
		<div>
			text before
			<b>bold</b>
			text after
		</div>
	);
	assert renderToString(node) === "<div>text before<b>bold</b>text after</div>", "both text runs survive";
}

// D2 attr classification: string literal → static attr, on* → event, any other
// expr → dynAttr thunk (same rule as dynText for expression children).

test "dynamic attr tracks its signal" {
	const [cls, setCls] = createSignal("red");
	const node = element(<p class={cls()}>x</p>);
	assert renderToString(node) === "<p class=\"red\">x</p>", "initial snapshot";
	setCls("blue");
	assert renderToString(node) === "<p class=\"blue\">x</p>", "snapshot follows set";
	assert node.attrs.length === 1, "one attr entry";
	assert node.attrs[0].isDyn, "expr attr classified dynamic";
}

test "string literal attr stays static, on* routes to events" {
	const [n, setN] = createSignal<number>(0);
	const node = element(<button type="button" onPress={() => setN(n() + 1)}>go</button>);
	assert renderToString(node) === "<button type=\"button\">go</button>", "event attr does not render";
	assert node.attrs.length === 1, "one attr entry";
	assert node.attrs[0].isDyn === false, "literal attr classified static";
	assert node.events.length === 1, "one event entry";
}

test "an inert expression is classified static, a call stays dynamic" {
	const label = "hi";
	const inert = element(<p class={label}>{label}</p>);
	assert inert.attrs.length === 1, "one attr entry";
	assert inert.attrs[0].isDyn === false, "identifier attr needs no thunk";
	assert inert.children.length === 1, "one child";
	assert inert.children[0].isDyn === false, "identifier child needs no thunk";
	assert renderToString(inert) === "<p class=\"hi\">hi</p>", "value: " + renderToString(inert);

	const [n, setN] = createSignal("a");
	const live = element(<p class={n()}>{n()}</p>);
	assert live.attrs[0].isDyn, "call attr stays dynamic";
	assert live.children[0].isDyn, "call child stays dynamic";
	setN("b");
	assert renderToString(live) === "<p class=\"b\">b</p>", "still reactive: " + renderToString(live);
}

test "mixed static and dynamic attrs keep source order" {
	const [x, setX] = createSignal("2");
	const node = element(<div a="1" b={x()} c="3"></div>);
	assert renderToString(node) === "<div a=\"1\" b=\"2\" c=\"3\"></div>", "source order preserved";
	setX("9");
	assert renderToString(node) === "<div a=\"1\" b=\"9\" c=\"3\"></div>", "middle attr updates in place";
}

test "the same JSX const consumed twice yields independent trees" {
	const [a, setA] = createSignal("x");
	const view = <p>{a()}</p>;
	const one = element(view);
	const two = element(view);
	setA("y");
	assert renderToString(one) === "<p>y</p>", "first tree reactive";
	assert renderToString(two) === "<p>y</p>", "second tree reactive";
}
