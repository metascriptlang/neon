import { createSignal } from "../../src/core/signal";
import { el, attr, text, dynText } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { element } from "../../src/macros/ui/element";
import { render, mockHost, mockNode, mockToString, fireEvent, Host, HostNode } from "../../src/render/host";

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

function writeCountingHost(attrWrites: number[], textWrites: number[]): Host {
	const h = mockHost();
	return {
		createElement: h.createElement, createText: h.createText,
		setText: (node: HostNode, value: string): void => {
			textWrites[0] = textWrites[0] + 1;
			h.setText(node, value);
		},
		setAttr: (node: HostNode, name: string, value: string): void => {
			attrWrites[0] = attrWrites[0] + 1;
			h.setAttr(node, name, value);
		},
		removeAttr: h.removeAttr, setStyle: h.setStyle, setStyleProp: h.setStyleProp, setStyleClass: h.setStyleClass, addEvent: h.addEvent,
		append: h.append, insertBefore: h.insertBefore, removeChild: h.removeChild,
		nextSibling: h.nextSibling, firstChild: h.firstChild, cloneNode: h.cloneNode,
	};
}

test "dynamic attr tracks its signal" {
	const [cls, setCls] = createSignal("red");
	const node = element(<p class={cls()}>x</p>);
	assert renderToString(node) === "<p class=\"red\">x</p>", "initial snapshot";
	setCls("blue");
	assert renderToString(node) === "<p class=\"blue\">x</p>", "snapshot follows set";

	const attrWrites: number[] = [0];
	const textWrites: number[] = [0];
	const root = mockNode("root");
	const [c2, setC2] = createSignal("red");
	const host = writeCountingHost(attrWrites, textWrites);
	const view = element(<p class={c2()}>x</p>);
	render(view, host, root as unknown as HostNode);
	assert attrWrites[0] === 2, "the first mount builds the skeleton's placeholder and binds the value, got " + attrWrites[0].toString();
	render(view, host, root as unknown as HostNode);
	assert attrWrites[0] === 3, "a later mount clones the skeleton and writes the attr once, got " + attrWrites[0].toString();
	setC2("blue");
	assert attrWrites[0] === 5, "the set writes each mounted attr once, got " + attrWrites[0].toString();
	assert mockToString(root) === "<root><p class=\"blue\">x</p><p class=\"blue\">x</p></root>", "value: " + mockToString(root);
}

test "string literal attr stays static, on* routes to events" {
	const [n, setN] = createSignal<number>(0);
	const attrWrites: number[] = [0];
	const textWrites: number[] = [0];
	const root = mockNode("root");
	render(
		element(<button type="button" onPress={() => setN(n() + 1)}>go</button>),
		writeCountingHost(attrWrites, textWrites),
		root as unknown as HostNode,
	);
	assert mockToString(root) === "<root><button type=\"button\">go</button></root>", "event attr does not render: " + mockToString(root);
	assert attrWrites[0] === 1, "the literal attr is the only attr write, got " + attrWrites[0].toString();

	fireEvent(root.children[0], "onPress");
	assert n() === 1, "onPress reached the handler";
	assert attrWrites[0] === 1, "a static attr is never rewritten, got " + attrWrites[0].toString();
}

test "an inert expression is classified static, a call stays dynamic" {
	const [n, setN] = createSignal("a");
	const label = n();

	const inertAttr: number[] = [0];
	const inertText: number[] = [0];
	const inertRoot = mockNode("root");
	render(element(<p class={label}>{label}</p>), writeCountingHost(inertAttr, inertText), inertRoot as unknown as HostNode);

	const liveAttr: number[] = [0];
	const liveText: number[] = [0];
	const liveRoot = mockNode("root");
	render(element(<p class={n()}>{n()}</p>), writeCountingHost(liveAttr, liveText), liveRoot as unknown as HostNode);

	assert mockToString(inertRoot) === mockToString(liveRoot), "same markup at mount: inert=" + mockToString(inertRoot) + " live=" + mockToString(liveRoot);
	assert inertText[0] === 1, "an identifier child fills its placeholder once, got " + inertText[0].toString();
	assert liveText[0] === 1, "a call child is bound and written once at mount, got " + liveText[0].toString();
	const inertAttrAtMount = inertAttr[0];
	const liveAttrAtMount = liveAttr[0];

	setN("b");
	assert inertAttr[0] === inertAttrAtMount, "an identifier attr subscribes to nothing, got " + inertAttr[0].toString();
	assert inertText[0] === 1, "an identifier child subscribes to nothing, got " + inertText[0].toString();
	assert liveAttr[0] === liveAttrAtMount + 1, "a call attr follows the signal, got " + liveAttr[0].toString();
	assert liveText[0] === 2, "a call child follows the signal, got " + liveText[0].toString();
	assert mockToString(inertRoot) === "<root><p class=\"a\">a</p></root>", "inert value: " + mockToString(inertRoot);
	assert mockToString(liveRoot) === "<root><p class=\"b\">b</p></root>", "live value: " + mockToString(liveRoot);
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
