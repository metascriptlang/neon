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

function Clicks(): NeonNode {
	let clicks = 0;
	const inc: (e: NeonEvent) => void = () => { clicks = clicks + 1; };
	return <button onPress={inc}>{clicks.toString()}</button>;
}

function counterTemplateV2<E>(__refreshEnv: E): NeonNode {
	const props = __refreshEnv.props;
	const count = __refreshEnv.count;
	const inc = __refreshEnv.inc;
	return <div>
		<p>{"t2 " + props.label() + ":" + count().toString()}</p>
		<button onPress={inc}>+</button>
	</div>;
}

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
	assert summary.kept === 6 && summary.remounted === 0, "three boundaries, three templates kept";
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
	assert summary.remounted === 1 && summary.kept === 4, "only Counter remounts";
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
	assert __refreshTmplSig_SameA() === __refreshTmplSig_SameB(), "equal JSX shares a signature";
	assert __refreshTmplSig_SameA() !== __refreshTmplSig_OtherText(), "JSX text is in it";
	const title = __refreshTmplSig_ReadsTitle();
	assert title !== __refreshTmplSig_ReadsLabel(), "member names are in it";
	assert __refreshSig_CountsOne() !== __refreshSig_CountsTwo(), "number literals are in it";
	assert __refreshSig_SameA() === __refreshSig_OtherText(), "JSX stays out of the setup";
}

test "refresh pass: a capitalized function that returns no NeonNode is left alone" {
	assert Plain() === "plain";
}

test "refresh pass: a template edit keeps the component's state" {
	refreshReset();
	const [root, dispose] = mountApp();
	const before = all(root, "button");
	for (let i = 0; i < 3; i += 1) { fireEvent(before[0], "onPress"); }
	const t2 = (): string => "t2";
	refreshTemplate(thisFile(), "Counter#template", counterTemplateV2, t2, __refreshSetup_Counter);
	const summary = refreshModule(thisFile());
	assert summary.rebuilt === 1 && summary.remounted === 0, "one template rebuilt, no remount";
	const rebuilt = texts(root);
	assert rebuilt === "<p>t2 a:3</p> <p>tally:0</p> ", "new template, count kept: " + rebuilt;
	fireEvent(all(root, "button")[0], "onPress");
	assert texts(root) === "<p>t2 a:4</p> <p>tally:0</p> ", "the kept handler adds one";
	dispose();
}

test "refresh pass: a re-evaluation with an unchanged module rebuilds what reads an import" {
	refreshReset();
	const [root, dispose] = mountApp();
	fireEvent(all(root, "button")[0], "onPress");
	const first = refreshModuleEval(thisFile(), "same", ["Counter#template"]);
	assert first.rebuilt === 0 && first.remounted === 0, "a first evaluation patches by signature";
	const again = refreshModuleEval(thisFile(), "same", ["Counter#template"]);
	assert again.rebuilt === 1 && again.remounted === 0, "the dependent template is rebuilt";
	assert texts(root) === "<p>a:1</p> <p>tally:0</p> ", "and keeps its state: " + texts(root);
	dispose();
}

test "refresh pass: a component whose template captures an assigned let keeps one boundary" {
	refreshReset();
	const root: MockNode = mockNode("root");
	const dispose = render(Clicks(), mockHost(), root as unknown as HostNode);
	const summary = refreshModule(thisFile());
	assert summary.kept === 1, "no template region: " + summary.kept.toString();
	dispose();
}
