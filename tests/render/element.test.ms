import { createSignal, Accessor } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { render, mockHost, mockNode, mockToString, fireEvent, Host, HostNode } from "../../src/render/host";
import { onCleanup } from "../../src/core/cleanup";
import { Show } from "../../src/macros/ui/flow";

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
		nextSibling: h.nextSibling, firstChild: h.firstChild, cloneNode: h.cloneNode, voidArea: h.voidArea, scrollTo: h.scrollTo,
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
	const inertTextAtMount = inertText[0];

	setN("b");
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
	assert mockToString(root) === "<root><p>NEON 5</p></root>", "after set: " + mockToString(root);
}

test "a reactive expression given to a function prop is read once, when the props are built" {
	const [loud, setLoud] = createSignal(true);
	const root = mockNode("root");
	render(element(<Picked data={words} format={loud() ? shout : quiet} />), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><p>NEON none</p></root>", "initial: " + mockToString(root);
	setLoud(false);
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
		value();
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
	assert mockToString(root) === "<root><div><h1>second</h1></div></root>", "slot contents remain reactive";
	assert mounts === 1 && cleanups === 0, "body read is untracked and update does not remount";
	setVisible(false);
	assert cleanups === 1, "owner disposes component once";
	setValue("third");
	assert mounts === 1 && cleanups === 1, "disposed slot does not run again";
}
