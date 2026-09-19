import { createSignal, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { render, mockHost, mockNode, mockToString, HostNode } from "../../src/render/host";
import { Show } from "../../src/macros/ui/flow";

interface LabelProps {
	label: Accessor<string>;
	count: Accessor<number>;
}

function AttrBare(props: LabelProps): NeonNode {
	return element(<p class={props.label}>x</p>);
}

function ChildBare(props: LabelProps): NeonNode {
	return element(<p>{props.label}</p>);
}

function ChildOperand(props: LabelProps): NeonNode {
	return element(<p>{props.label + ":" + (props.count * 2).toString()}</p>);
}

function ChildReceiver(props: LabelProps): NeonNode {
	return element(<p>{props.count.toString()}</p>);
}

function Inner(props: LabelProps): NeonNode {
	return element(<i title={props.label}>{props.label}</i>);
}

function Outer(props: LabelProps): NeonNode {
	return element(<Inner label={props.label} count={props.count} />);
}

test "a bare accessor prop in an attribute stays reactive" {
	const [l, setL] = createSignal("a");
	const [n, setN] = createSignal<number>(1);
	const root = mockNode("root");
	render(element(<AttrBare label={l} count={n} />), mockHost(), root as unknown as HostNode);
	setL("b");
	assert mockToString(root) === "<root><p class=\"b\">x</p></root>", "attr: " + mockToString(root);
}

test "a bare accessor prop as a child stays reactive" {
	const [l, setL] = createSignal("a");
	const [n, setN] = createSignal<number>(1);
	const root = mockNode("root");
	render(element(<ChildBare label={l} count={n} />), mockHost(), root as unknown as HostNode);
	setL("b");
	assert mockToString(root) === "<root><p>b</p></root>", "child: " + mockToString(root);
}

test "an accessor operand in a child stays reactive" {
	const [l, setL] = createSignal("a");
	const [n, setN] = createSignal<number>(1);
	const root = mockNode("root");
	render(element(<ChildOperand label={l} count={n} />), mockHost(), root as unknown as HostNode);
	setN(5);
	assert mockToString(root) === "<root><p>a:10</p></root>", "operand: " + mockToString(root);
}

test "an accessor receiver in a child stays reactive" {
	const [l, setL] = createSignal("a");
	const [n, setN] = createSignal<number>(1);
	const root = mockNode("root");
	render(element(<ChildReceiver label={l} count={n} />), mockHost(), root as unknown as HostNode);
	setN(7);
	assert mockToString(root) === "<root><p>7</p></root>", "receiver: " + mockToString(root);
}

test "an accessor prop passed through a second component stays reactive" {
	const [l, setL] = createSignal("a");
	const [n, setN] = createSignal<number>(1);
	const root = mockNode("root");
	render(element(<Outer label={l} count={n} />), mockHost(), root as unknown as HostNode);
	setL("b");
	assert mockToString(root) === "<root><i title=\"b\">b</i></root>", "pass-through: " + mockToString(root);
}

test "a top-level signal read bare in an attribute and a child stays reactive" {
	const [l, setL] = createSignal("a");
	const root = mockNode("root");
	render(element(<p class={l}>{l}</p>), mockHost(), root as unknown as HostNode);
	setL("b");
	assert mockToString(root) === "<root><p class=\"b\">b</p></root>", "signal: " + mockToString(root);
}

test "a bare boolean accessor guarding a child toggles it" {
	const [on, setOn] = createSignal(false);
	const root = mockNode("root");
	render(element(<div>{on && <span>yes</span>}</div>), mockHost(), root as unknown as HostNode);
	const before = mockToString(root);
	setOn(true);
	const after = mockToString(root);
	assert after.indexOf("yes") >= 0 && before.indexOf("yes") < 0, "toggle: " + before + " -> " + after;
}
