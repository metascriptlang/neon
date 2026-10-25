import { createSignal, untrack, Accessor } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { render, mockHost, mockNode, mockToString, fireEvent, Host, HostNode, MockNode } from "../../src/render/host";
import { onCleanup } from "../../src/core/cleanup";
import { Show } from "../../src/macros/ui/flow";
import { flush } from "../../src/core/runtime";

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
		append: h.append, insertBefore: h.insertBefore, removeChild: h.removeChild, parentOf: h.parentOf, release: h.release,
		nextSibling: h.nextSibling, firstChild: h.firstChild, cloneNode: h.cloneNode, voidArea: h.voidArea, scrollTo: h.scrollTo, measureText: h.measureText,
	};
}

test "a template mount builds the skeleton once and clones it after" {
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
	flush();
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
	flush();
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
	const inertTextAtMount = inertText[0];

	setN("b");
	flush();
	assert inertAttr[0] === inertAttrAtMount, "an identifier attr subscribes to nothing, got " + inertAttr[0].toString();
	assert inertText[0] === inertTextAtMount, "an identifier child subscribes to nothing, got " + inertText[0].toString();
	assert liveAttr[0] === liveAttrAtMount + 1, "a call attr follows the signal, got " + liveAttr[0].toString();
	assert liveText[0] === 2, "a call child follows the signal, got " + liveText[0].toString();
	assert mockToString(inertRoot) === "<root><p class=\"a\">a</p></root>", "inert value: " + mockToString(inertRoot);
	assert mockToString(liveRoot) === "<root><p class=\"b\">b</p></root>", "live value: " + mockToString(liveRoot);
}

function Picked<T>(props: { data: Accessor<T[]>; format: (item: T) => string; onEndReachedThreshold?: Accessor<number> | null }): NeonNode {
	const threshold = props.onEndReachedThreshold;
	return element(<p>{props.format(props.data()[0]) + " " + (threshold === null ? "none" : (threshold as Accessor<number>)().toString())}</p>);
}

function shout(w: string): string { return w.toUpperCase(); }
function quiet(w: string): string { return w; }
const words: string[] = ["neon", "void"];

test "an on-named Accessor prop takes a reactive expression" {
	const [limit, setLimit] = createSignal<number>(4);
	const root = mockNode("root");
	render(element(<Picked data={words} format={shout} onEndReachedThreshold={limit()} />), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><p>NEON 4</p></root>", "initial: " + mockToString(root);
	setLimit(5);
	flush();
	assert mockToString(root) === "<root><p>NEON 5</p></root>", "after set: " + mockToString(root);
}

test "a reactive expression given to a function prop is read once, when the props are built" {
	const [loud, setLoud] = createSignal(true);
	const root = mockNode("root");
	render(element(<Picked data={words} format={loud() ? shout : quiet} />), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><p>NEON none</p></root>", "initial: " + mockToString(root);
	setLoud(false);
	flush();
	assert mockToString(root) === "<root><p>NEON none</p></root>", "the chosen function stays: " + mockToString(root);
}

function NodeSlot(props: { content: NeonNode | null }): NeonNode {
	const content = props.content;
	if (content === null) { return element(<i>empty</i>); }
	return content;
}

test "node slot component mounts once untracked and cleans up with its owner" {
	const [value, setValue] = createSignal("first");
	const [visible, setVisible] = createSignal(true);
	let mounts = 0;
	let cleanups = 0;
	const Heading = (): NeonNode => {
		mounts = mounts + 1;
		untrack((): string => value());
		onCleanup((): void => { cleanups = cleanups + 1; });
		return element(<h1>{value()}</h1>);
	};
	const view = element(<div><Show when={visible()}><NodeSlot content={Heading} /></Show></div>);
	assert mounts === 0, "props construction does not call the component";
	const root = mockNode("root");
	render(view, mockHost(), root as unknown as HostNode);
	assert mounts === 1, "component mounts once";
	assert mockToString(root) === "<root><div><h1>first</h1></div></root>", "initial content";
	setValue("second");
	flush();
	assert mockToString(root) === "<root><div><h1>second</h1></div></root>", "slot contents remain reactive";
	assert mounts === 1 && cleanups === 0, "body read is untracked and update does not remount";
	setVisible(false);
	flush();
	assert cleanups === 1, "owner disposes component once";
	setValue("third");
	flush();
	assert mounts === 1 && cleanups === 1, "disposed slot does not run again";
}

function mounted(view: NeonNode): MockNode {
	const root = mockNode("root");
	render(view, mockHost(), root as unknown as HostNode);
	return root;
}

test "reactive element renders and updates on signal change" {
	const [name, setName] = createSignal("world");
	const root = mounted(element(<p>Hi {name()}</p>));
	assert mockToString(root) === "<root><p>Hi world</p></root>", "initial render: " + mockToString(root);
	setName("neon");
	flush();
	assert mockToString(root) === "<root><p>Hi neon</p></root>", "render updates after set: " + mockToString(root);
}

test "JSX bound to a const is consumed by element()" {
	const [name, setName] = createSignal("world");
	const view = <p>Hi {name()}</p>;
	const root = mounted(element(view));
	assert mockToString(root) === "<root><p>Hi world</p></root>", "const-form initial render: " + mockToString(root);
	setName("neon");
	flush();
	assert mockToString(root) === "<root><p>Hi neon</p></root>", "const-form updates after set: " + mockToString(root);
}

test "whitespace-only children between elements are dropped" {
	const root = mounted(element(
		<div>
			<p>x</p>
			<b>y</b>
		</div>
	));
	assert mockToString(root) === "<root><div><p>x</p><b>y</b></div></root>", "indentation between elements: " + mockToString(root);
}

test "a same-line space between elements is significant and kept" {
	const root = mounted(element(<p><b>a</b> <i>c</i></p>));
	assert mockToString(root) === "<root><p><b>a</b> <i>c</i></p></root>", "single space has no newline: " + mockToString(root);
}

test "text spanning lines is rejoined with single spaces" {
	const root = mounted(element(
		<p>
			hello
			world
		</p>
	));
	assert mockToString(root) === "<root><p>hello world</p></root>", "indentation stripped, lines joined: " + mockToString(root);
}

test "text alone on its own line keeps its content" {
	const withAttr = mounted(element(
		<p data-a="1">
			hello
		</p>
	));
	assert mockToString(withAttr) === "<root><p data-a=\"1\">hello</p></root>", "attributed element keeps text: " + mockToString(withAttr);
	const noAttr = mounted(element(
		<p>
			hello
		</p>
	));
	assert mockToString(noAttr) === "<root><p>hello</p></root>", "unattributed element keeps text: " + mockToString(noAttr);
}

test "single-line text passes through byte for byte" {
	const trailing = mounted(element(<p>Count: </p>));
	assert mockToString(trailing) === "<root><p>Count: </p></root>", "trailing space kept: " + mockToString(trailing);
	const padded = mounted(element(<p>  spaced  </p>));
	assert mockToString(padded) === "<root><p>  spaced  </p></root>", "inner padding kept: " + mockToString(padded);
}

test "text around an element on separate lines keeps both runs" {
	const root = mounted(element(
		<div>
			text before
			<b>bold</b>
			text after
		</div>
	));
	assert mockToString(root) === "<root><div>text before<b>bold</b>text after</div></root>", "both text runs survive: " + mockToString(root);
}

test "dynamic attr tracks its signal" {
	const [cls, setCls] = createSignal("red");
	const root = mounted(element(<p class={cls()}>x</p>));
	assert mockToString(root) === "<root><p class=\"red\">x</p></root>", "initial snapshot: " + mockToString(root);
	setCls("blue");
	flush();
	assert mockToString(root) === "<root><p class=\"blue\">x</p></root>", "snapshot follows set: " + mockToString(root);
}

test "mixed static and dynamic attrs keep source order" {
	const [x, setX] = createSignal("2");
	const root = mounted(element(<div data-a="1" data-b={x()} data-c="3"></div>));
	assert mockToString(root) === "<root><div data-a=\"1\" data-b=\"2\" data-c=\"3\"></div></root>", "source order preserved: " + mockToString(root);
	setX("9");
	flush();
	assert mockToString(root) === "<root><div data-a=\"1\" data-b=\"9\" data-c=\"3\"></div></root>", "middle attr updates in place: " + mockToString(root);
}

test "the same JSX const consumed twice yields independent trees" {
	const [a, setA] = createSignal("x");
	const view = <p>{a()}</p>;
	const one = mounted(element(view));
	const two = mounted(element(view));
	assert mockToString(one) === "<root><p>x</p></root>" && mockToString(two) === "<root><p>x</p></root>", "both trees start alike: " + mockToString(one) + " " + mockToString(two);
	setA("y");
	flush();
	assert mockToString(one) === "<root><p>y</p></root>", "first tree reactive: " + mockToString(one);
	assert mockToString(two) === "<root><p>y</p></root>", "second tree reactive: " + mockToString(two);
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

function twice(n: number): string { return (n * 2).toString(); }

test "a named function crosses to a component's function prop as written" {
	const plain = mounted(element(<Limited label="x" format={twice} />));
	assert mockToString(plain) === "<root><p>x 2 none</p></root>", "non-generic: " + mockToString(plain);
	const generic = mounted(element(<Picked data={words} format={shout} />));
	assert mockToString(generic) === "<root><p>NEON none</p></root>", "generic, T bound by the named function: " + mockToString(generic);
}

test "an on-named Accessor prop takes a literal" {
	const plain = mounted(element(<Limited label="x" format={twice} onEndReachedThreshold={2} />));
	assert mockToString(plain) === "<root><p>x 2 2</p></root>", "non-generic literal: " + mockToString(plain);
	const generic = mounted(element(<Picked data={words} format={shout} onEndReachedThreshold={3} />));
	assert mockToString(generic) === "<root><p>NEON 3</p></root>", "generic literal: " + mockToString(generic);
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
	const heading = "<root><h1>heading</h1></root>";
	assert mockToString(mounted(element(<NodeSlot content={SlotHeading} />))) === heading, "named component";
	assert mockToString(mounted(element(<NodeSlot content={element(<SlotHeading />)} />))) === heading, "existing element";
	assert mockToString(mounted(element(<NodeSlot content={SlotHeading()} />))) === heading, "existing NeonNode";
	assert mockToString(mounted(element(<NodeSlot content={null} />))) === "<root><i>empty</i></root>", "nullable slot";
	assert mockToString(mounted(element(<NodeSlot content={OptionalSlotHeading} />))) === heading, "optional props receive an empty object";
	assert mockToString(mounted(element(<NodeSlot content={slotComponents.Heading} />))) === heading, "dotted component";
	assert mockToString(mounted(element(<NodeSlot content={(): NeonNode => element(<h1>heading</h1>)} />))) === heading, "inline component";
	assert mockToString(mounted(element(<NodeSlot content={<SlotHeading />} />))) === heading, "JSX element slot";
	assert mockToString(mounted(element(<NodeSlot content={() => element(<h1>heading</h1>)} />))) === heading, "inferred inline component";
	assert mockToString(mounted(element(<NodeSlot content={<RequiredSlotHeading title="heading" />} />))) === heading, "required props are supplied on an element";
}

test "generic consumers normalize node slots without converting ordinary callbacks" {
	const both = "<root><div><b>NEON</b><h1>heading</h1></div></root>";
	assert mockToString(mounted(element(<GenericNodeSlot item="neon" format={shout} content={SlotHeading} />))) === both, "generic named slot";
	assert mockToString(mounted(element(<GenericNodeSlot item="neon" format={shout} content={element(<SlotHeading />)} />))) === both, "generic element slot";
	assert mockToString(mounted(element(<GenericNodeSlot item="neon" format={shout} content={<SlotHeading />} />))) === both, "generic raw JSX slot";
}

function CallbackSlot(props: { make: () => NeonNode }): NeonNode {
	return props.make();
}

test "a component-valued ordinary callback prop is not normalized" {
	assert mockToString(mounted(element(<CallbackSlot make={SlotHeading} />))) === "<root><h1>heading</h1></root>", "callback remains callable";
}

test "number and boolean attribute values lower to the strings HTML reads" {
	const [locked, setLocked] = createSignal(true);
	const [span, setSpan] = createSignal(2);
	const shown = false;
	const root = mounted(element(
		<div tabindex={3} hidden={shown} draggable={shown} spellcheck>
			<input disabled={locked()} readonly />
			<td colspan={span()} rowspan={1.5} />
		</div>
	));
	assert mockToString(root) === "<root><div tabindex=\"3\" draggable=\"false\" spellcheck=\"true\"><input disabled=\"\" readonly=\"\"></input><td colspan=\"2\" rowspan=\"1.5\"></td></div></root>", "lowered: " + mockToString(root);
	setLocked(false);
	setSpan(4);
	flush();
	assert mockToString(root) === "<root><div tabindex=\"3\" draggable=\"false\" spellcheck=\"true\"><input readonly=\"\"></input><td colspan=\"4\" rowspan=\"1.5\"></td></div></root>", "followed: " + mockToString(root);
}

test "a nullable number or boolean attribute is removed by null and lowered otherwise" {
	const [span, setSpan] = createSignal<number | null>(3);
	const [open, setOpen] = createSignal<boolean | null>(null);
	const root = mounted(element(<details open={open()}><td colspan={span()} /></details>));
	assert mockToString(root) === "<root><details><td colspan=\"3\"></td></details></root>", "first: " + mockToString(root);
	setSpan(null);
	setOpen(true);
	flush();
	assert mockToString(root) === "<root><details open=\"\"><td></td></details></root>", "after: " + mockToString(root);
}
