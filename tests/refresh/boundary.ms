import { createSignal, Accessor } from "../../src/core/signal";
import { NeonEvent } from "../../src/render/event";
import {
	HostNode,
	MockNode,
	mockNode,
	mockHost,
	render,
	fireEvent,
	mockToString,
} from "../../src/render/host";
import { refreshReset } from "../../src/render/refresh";
import { thisFile } from "./here";

interface CounterProps {
	label: Accessor<string>;
}

function Counter(props: CounterProps): NeonNode {
	const [count, setCount] = createSignal(0);
	const inc: (e: NeonEvent) => void = () => { setCount(count() + 1); };
	return <div>
		<p>{props.label() + ":" + count().toString()}</p>
		<button onPress={inc}>+</button>
	</div>;
}

interface TallyProps {
	name: Accessor<string>;
}

function Tally(props: TallyProps): NeonNode {
	const [count, setCount] = createSignal(0);
	const inc: (e: NeonEvent) => void = () => { setCount(count() + 1); };
	return <div>
		<p>{props.name() + ":" + count().toString()}</p>
		<button onPress={inc}>+</button>
	</div>;
}

function App(): NeonNode {
	return <section><Counter label="a" /><Tally name="tally" /></section>;
}

function counterV2(props: CounterProps): NeonNode {
	const [count, setCount] = createSignal(0);
	const inc: (e: NeonEvent) => void = () => { setCount(count() + 10); };
	return <div>
		<p>{"v2 " + props.label() + ":" + count().toString()}</p>
		<button onPress={inc}>+</button>
	</div>;
}

function SameA(): NeonNode { return <p>same</p>; }
function SameB(): NeonNode { return <p>same</p>; }
function OtherText(): NeonNode { return <p>other</p>; }

interface TitleProps {
	title: Accessor<string>;
	label: Accessor<string>;
}

function ReadsTitle(props: TitleProps): NeonNode { return <p>{props.title()}</p>; }
function ReadsLabel(props: TitleProps): NeonNode { return <p>{props.label()}</p>; }
function CountsOne(): NeonNode { const n = 1; return <p>{n.toString()}</p>; }
function CountsTwo(): NeonNode { const n = 2; return <p>{n.toString()}</p>; }

function Plain(): string { return "plain"; }

function mountApp(): [MockNode, () => void] {
	const root: MockNode = mockNode("root");
	const dispose = render(App(), mockHost(), root as unknown as HostNode);
	return [root, dispose];
}

function collect(node: MockNode, tag: string, into: MockNode[]): void {
	if (node.tag === tag) { into.push(node); }
	for (const child of node.children) { collect(child, tag, into); }
}

function all(root: MockNode, tag: string): MockNode[] {
	const found: MockNode[] = [];
	collect(root, tag, found);
	return found;
}

function texts(root: MockNode): string {
	let out = "";
	for (const p of all(root, "p")) { out = out + mockToString(p) + " "; }
	return out;
}

test "refresh pass: a component mounts through its boundary and keeps its view" {
	refreshReset();
	const [root, dispose] = mountApp();
	const buttons = all(root, "button");
	for (let i = 0; i < 3; i += 1) { fireEvent(buttons[0], "onPress"); }
	assert texts(root) === "<p>a:3</p> <p>tally:0</p> ", "clicks reach it: " + texts(root);
	const summary = refreshModule(thisFile());
	assert summary.kept === 3 && summary.remounted === 0, "App, Counter and Tally kept";
	assert texts(root) === "<p>a:3</p> <p>tally:0</p> ", "an unchanged module keeps state";
	dispose();
}

test "refresh pass: a changed component remounts alone, its sibling keeps state" {
	refreshReset();
	const [root, dispose] = mountApp();
	const before = all(root, "button");
	for (let i = 0; i < 3; i += 1) { fireEvent(before[0], "onPress"); }
	fireEvent(before[1], "onPress");
	const v2 = (): string => "v2";
	refreshComponent<CounterProps>(thisFile(), "Counter|CounterProps", counterV2, v2);
	const summary = refreshModule(thisFile());
	assert summary.remounted === 1 && summary.kept === 2, "only Counter remounts";
	const remounted = texts(root);
	assert remounted === "<p>v2 a:0</p> <p>tally:1</p> ", "new code, local reset: " + remounted;
	const after = all(root, "button");
	fireEvent(after[0], "onPress");
	assert texts(root) === "<p>v2 a:10</p> <p>tally:1</p> ", "the new handler runs once";
	fireEvent(before[0], "onPress");
	assert texts(root) === "<p>v2 a:10</p> <p>tally:1</p> ", "the old handler is gone";
	dispose();
}

test "refresh pass: the signature follows text, member names and literals" {
	assert __refreshSig_SameA() === __refreshSig_SameB(), "equal bodies share a signature";
	assert __refreshSig_SameA() !== __refreshSig_OtherText(), "JSX text is in it";
	assert __refreshSig_ReadsTitle() !== __refreshSig_ReadsLabel(), "member names are in it";
	assert __refreshSig_CountsOne() !== __refreshSig_CountsTwo(), "number literals are in it";
}

test "refresh pass: a capitalized function that returns no NeonNode is left alone" {
	assert Plain() === "plain";
}
