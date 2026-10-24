import { createSignal, Accessor } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { element } from "../../src/macros/ui/element";

test "reactive element renders and updates on signal change" {
	const [name, setName] = createSignal("world");
	const node = element(<p>Hi {name()}</p>);
	assert renderToString(node) === "<p>Hi <!--!-->world</p>", "initial render";
	setName("neon");
	assert renderToString(node) === "<p>Hi <!--!-->neon</p>", "render updates after set";
}

test "JSX bound to a const is consumed by element()" {
	const [name, setName] = createSignal("world");
	const view = <p>Hi {name()}</p>;
	const node = element(view);
	assert renderToString(node) === "<p>Hi <!--!-->world</p>", "const-form initial render";
	setName("neon");
	assert renderToString(node) === "<p>Hi <!--!-->neon</p>", "const-form updates after set";
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
		<p data-a="1">
			hello
		</p>
	);
	assert renderToString(withAttr) === "<p data-a=\"1\">hello</p>", "attributed element keeps text";
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

test "dynamic attr tracks its signal" {
	const [cls, setCls] = createSignal("red");
	const node = element(<p class={cls()}>x</p>);
	assert renderToString(node) === "<p class=\"red\">x</p>", "initial snapshot";
	setCls("blue");
	assert renderToString(node) === "<p class=\"blue\">x</p>", "snapshot follows set";
}

test "mixed static and dynamic attrs keep source order" {
	const [x, setX] = createSignal("2");
	const node = element(<div data-a="1" data-b={x()} data-c="3"></div>);
	assert renderToString(node) === "<div data-a=\"1\" data-b=\"2\" data-c=\"3\"></div>", "source order preserved";
	setX("9");
	assert renderToString(node) === "<div data-a=\"1\" data-b=\"9\" data-c=\"3\"></div>", "middle attr updates in place";
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

interface Limits {
	label: string;
	format: (n: number) => string;
	onEndReachedThreshold?: Accessor<number> | null;
}

function Limited(props: Limits): NeonNode {
	const threshold = props.onEndReachedThreshold;
	return element(<p>{props.label + " " + props.format(1) + " " + (threshold === null ? "none" : (threshold as Accessor<number>)().toString())}</p>);
}

function Picked<T>(props: { data: Accessor<T[]>; format: (item: T) => string; onEndReachedThreshold?: Accessor<number> | null }): NeonNode {
	const threshold = props.onEndReachedThreshold;
	return element(<p>{props.format(props.data()[0]) + " " + (threshold === null ? "none" : (threshold as Accessor<number>)().toString())}</p>);
}

function twice(n: number): string { return (n * 2).toString(); }
function shout(w: string): string { return w.toUpperCase(); }
const words: string[] = ["neon", "void"];

test "a named function crosses to a component's function prop as written" {
	assert renderToString(element(<Limited label="x" format={twice} />)) === "<p>x 2 none</p>", "non-generic";
	assert renderToString(element(<Picked data={words} format={shout} />)) === "<p>NEON none</p>", "generic, T bound by the named function";
}

test "an on-named Accessor prop takes a literal" {
	assert renderToString(element(<Limited label="x" format={twice} onEndReachedThreshold={2} />)) === "<p>x 2 2</p>", "non-generic literal";
	assert renderToString(element(<Picked data={words} format={shout} onEndReachedThreshold={3} />)) === "<p>NEON 3</p>", "generic literal";
}

function NodeSlot(props: { content: NeonNode | null }): NeonNode {
	const content = props.content;
	if (content === null) { return element(<i>empty</i>); }
	return content;
}

function GenericNodeSlot<T>(props: { item: T; format: (item: T) => string; content: NeonNode }): NeonNode {
	return element(<div><b>{props.format(props.item)}</b>{props.content}</div>);
}

function SlotHeading(): NeonNode {
	return element(<h1>heading</h1>);
}

function OptionalSlotHeading(props: { label?: string | null }): NeonNode {
	return element(<h1>{props.label ?? "heading"}</h1>);
}

function RequiredSlotHeading(props: { title: string }): NeonNode {
	return element(<h1>{props.title}</h1>);
}

interface SlotComponents {
	Heading: () => NeonNode;
}

const slotComponents: SlotComponents = { Heading: SlotHeading };

test "declared node slots accept named components and existing elements equivalently" {
	assert renderToString(element(<NodeSlot content={SlotHeading} />)) === "<h1>heading</h1>", "named component";
	assert renderToString(element(<NodeSlot content={element(<SlotHeading />)} />)) === "<h1>heading</h1>", "existing element";
	assert renderToString(element(<NodeSlot content={SlotHeading()} />)) === "<h1>heading</h1>", "existing NeonNode";
	assert renderToString(element(<NodeSlot content={null} />)) === "<i>empty</i>", "nullable slot";
	assert renderToString(element(<NodeSlot content={OptionalSlotHeading} />)) === "<h1>heading</h1>", "optional props receive an empty object";
	assert renderToString(element(<NodeSlot content={slotComponents.Heading} />)) === "<h1>heading</h1>", "dotted component";
	assert renderToString(element(<NodeSlot content={(): NeonNode => element(<h1>heading</h1>)} />)) === "<h1>heading</h1>", "inline component";
	assert renderToString(element(<NodeSlot content={<SlotHeading />} />)) === "<h1>heading</h1>", "JSX element slot";
	assert renderToString(element(<NodeSlot content={() => element(<h1>heading</h1>)} />)) === "<h1>heading</h1>", "inferred inline component";
	assert renderToString(element(<NodeSlot content={<RequiredSlotHeading title="heading" />} />)) === "<h1>heading</h1>", "required props are supplied on an element";
}

test "generic consumers normalize node slots without converting ordinary callbacks" {
	assert renderToString(element(<GenericNodeSlot item="neon" format={shout} content={SlotHeading} />)) === "<div><b>NEON</b><h1>heading</h1></div>", "generic named slot";
	assert renderToString(element(<GenericNodeSlot item="neon" format={shout} content={element(<SlotHeading />)} />)) === "<div><b>NEON</b><h1>heading</h1></div>", "generic element slot";
	assert renderToString(element(<GenericNodeSlot item="neon" format={shout} content={<SlotHeading />} />)) === "<div><b>NEON</b><h1>heading</h1></div>", "generic raw JSX slot";
}

function CallbackSlot(props: { make: () => NeonNode }): NeonNode {
	return props.make();
}

test "a component-valued ordinary callback prop is not normalized" {
	assert renderToString(element(<CallbackSlot make={SlotHeading} />)) === "<h1>heading</h1>", "callback remains callable";
}
