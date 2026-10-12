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

interface RowProps {
	label: Accessor<string>;
}

function Row(props: RowProps): NeonNode {
	const [count, setCount] = createSignal(0);
	const inc: (e: NeonEvent) => void = () => { setCount(count() + 1); };
	return <div>
		<p>{props.label() + ":" + count().toString()}</p>
		<button onPress={inc}>+</button>
	</div>;
}

function RowByTen(props: RowProps): NeonNode {
	const [count, setCount] = createSignal(0);
	const inc: (e: NeonEvent) => void = () => { setCount(count() + 10); };
	return <div>
		<p>{"ten " + props.label() + ":" + count().toString()}</p>
		<button onPress={inc}>+</button>
	</div>;
}

function RowFromFive(props: RowProps): NeonNode {
	const [count, setCount] = createSignal(5);
	const inc: (e: NeonEvent) => void = () => { setCount(count() + 1); };
	return <div>
		<p>{"five " + props.label() + ":" + count().toString()}</p>
		<button onPress={inc}>+</button>
	</div>;
}

function RowWithStep(props: RowProps): NeonNode {
	const [step, setStep] = createSignal(2);
	const [count, setCount] = createSignal(0);
	const inc: (e: NeonEvent) => void = () => { setCount(count() + step()); };
	return <div>
		<p>{props.label() + ":" + count().toString() + "/" + step().toString()}</p>
		<button onPress={inc}>+</button>
	</div>;
}

function Gauge(): NeonNode {
	const start = 3;
	const [level, setLevel] = createSignal(start);
	const up: (e: NeonEvent) => void = () => { setLevel(level() + 1); };
	return <div>
		<p>{"level " + level().toString()}</p>
		<button onPress={up}>+</button>
	</div>;
}

function GaugeNamed(): NeonNode {
	const start = "three";
	const [level, setLevel] = createSignal(start);
	const up: (e: NeonEvent) => void = () => { setLevel(level() + "!"); };
	return <div>
		<p>{"level " + level()}</p>
		<button onPress={up}>+</button>
	</div>;
}

function List(): NeonNode {
	return <section><Row label="a" /><Row label="b" /></section>;
}

function listTemplateV2<E>(__refreshEnv: E): NeonNode {
	return <section><h1>v2</h1><Row label="a" /><Row label="b" /></section>;
}

function Frame(): NeonNode {
	const [title, setTitle] = createSignal("frame");
	const rename: (e: NeonEvent) => void = () => { setTitle(title() + "!"); };
	return <section>
		<p>{title()}</p>
		<button onPress={rename}>r</button>
		<Row label="a" />
	</section>;
}

function FrameLoud(): NeonNode {
	const [title, setTitle] = createSignal("frame");
	const rename: (e: NeonEvent) => void = () => { setTitle(title() + "?"); };
	return <section>
		<p>{"loud " + title()}</p>
		<button onPress={rename}>r</button>
		<Row label="a" />
	</section>;
}

function Late(): NeonNode {
	const [first, setFirst] = createSignal(false);
	const open: (e: NeonEvent) => void = () => { setFirst(true); };
	return <section>
		<button onPress={open}>open</button>
		<Show when={first()}><Row label="x" /></Show>
		<Row label="y" />
	</section>;
}

function lateTemplateV2<E>(__refreshEnv: E): NeonNode {
	const first = __refreshEnv.first;
	const open = __refreshEnv.open;
	return <section>
		<h1>v2</h1>
		<button onPress={open}>open</button>
		<Show when={first()}><Row label="x" /></Show>
		<Row label="y" />
	</section>;
}

function tallyCell(label: string): NeonNode {
	const [n, setN] = createSignal(0);
	refreshKeep("cell", (): int32 => n(), (value: int32): void => { setN(value); });
	const inc: (e: NeonEvent) => void = () => { setN(n() + 1); };
	return <div>
		<p>{label + "=" + n().toString()}</p>
		<button onPress={inc}>+</button>
	</div>;
}

function Board(): NeonNode {
	const [names, setNames] = createSignal(["p", "q"]);
	return <section>
		<For each={names()}>{(name: string, i: Accessor<number>): NeonNode => tallyCell(name)}</For>
	</section>;
}

function boardTemplateV2<E>(__refreshEnv: E): NeonNode {
	const names = __refreshEnv.names;
	return <section>
		<h1>v2</h1>
		<For each={names()}>{(name: string, i: Accessor<number>): NeonNode => tallyCell(name)}</For>
	</section>;
}

function boardBodyV2(): NeonNode {
	const [names, setNames] = createSignal(["p", "q"]);
	return refreshRegion(thisFile(), "Board#template", __refreshTmpl_Board, __refreshTmplSig_Board, { names: names });
}

function mount(node: NeonNode): [MockNode, () => void] {
	const root: MockNode = mockNode("root");
	const dispose = render(node, mockHost(), root as unknown as HostNode);
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

function press(root: MockNode, at: int32, times: int32): void {
	for (let i = 0 as int32; i < times; i += 1) { fireEvent(all(root, "button")[at], "onPress"); }
}

const edited = (): string => "edited";

test "refresh state: a setup edit keeps the component's signals" {
	refreshReset();
	const [root, dispose] = mount(List());
	press(root, 0, 3);
	press(root, 1, 1);
	refreshComponent<RowProps>(thisFile(), "Row|RowProps", __refreshBody_RowByTen, edited);
	const summary = refreshModule(thisFile());
	assert summary.remounted === 2, "both rows remount: " + summary.remounted.toString();
	assert texts(root) === "<p>ten a:3</p> <p>ten b:1</p> ", "new code, counts kept: " + texts(root);
	press(root, 0, 1);
	assert texts(root) === "<p>ten a:13</p> <p>ten b:1</p> ", "the new handler runs: " + texts(root);
	dispose();
}

test "refresh state: an edited state declaration starts again" {
	refreshReset();
	const [root, dispose] = mount(List());
	press(root, 0, 3);
	refreshComponent<RowProps>(thisFile(), "Row|RowProps", __refreshBody_RowFromFive, edited);
	refreshModule(thisFile());
	assert texts(root) === "<p>five a:5</p> <p>five b:5</p> ", "the new initial value shows: " + texts(root);
	dispose();
}

test "refresh state: a new signal joins the kept ones" {
	refreshReset();
	const [root, dispose] = mount(List());
	press(root, 0, 3);
	refreshComponent<RowProps>(thisFile(), "Row|RowProps", __refreshBody_RowWithStep, edited);
	refreshModule(thisFile());
	assert texts(root) === "<p>a:3/2</p> <p>b:0/2</p> ", "count kept beside the new step: " + texts(root);
	press(root, 0, 1);
	assert texts(root) === "<p>a:5/2</p> <p>b:0/2</p> ", "the new handler reads both: " + texts(root);
	dispose();
}

test "refresh state: a signal whose type changed starts again" {
	refreshReset();
	const [root, dispose] = mount(Gauge());
	press(root, 0, 2);
	assert texts(root) === "<p>level 5</p> ", texts(root);
	refreshComponent0(thisFile(), "Gauge|", __refreshBody_GaugeNamed, edited);
	refreshModule(thisFile());
	assert texts(root) === "<p>level three</p> ", "the number is not read as a string: " + texts(root);
	dispose();
}

test "refresh state: a parent's template edit keeps its children's signals" {
	refreshReset();
	const [root, dispose] = mount(List());
	press(root, 0, 3);
	press(root, 1, 1);
	refreshTemplate0(thisFile(), "List#template", listTemplateV2, edited, __refreshSetup_List);
	const summary = refreshModule(thisFile());
	assert summary.rebuilt === 1 && summary.remounted === 0, "one template rebuilt";
	assert all(root, "h1").length === 1, "the new template is mounted";
	assert texts(root) === "<p>a:3</p> <p>b:1</p> ", "each row keeps its own count: " + texts(root);
	dispose();
}

test "refresh state: a parent's setup edit keeps its own and its children's signals" {
	refreshReset();
	const [root, dispose] = mount(Frame());
	press(root, 0, 1);
	press(root, 1, 4);
	assert texts(root) === "<p>frame!</p> <p>a:4</p> ", texts(root);
	refreshComponent0(thisFile(), "Frame|", __refreshBody_FrameLoud, edited);
	const summary = refreshModule(thisFile());
	assert summary.remounted === 1, "only the frame remounts: " + summary.remounted.toString();
	assert texts(root) === "<p>loud frame!</p> <p>a:4</p> ", "title and row count kept: " + texts(root);
	dispose();
}

test "refresh state: children are matched in document order, not in mount order" {
	refreshReset();
	const [root, dispose] = mount(Late());
	press(root, 1, 2);
	press(root, 0, 1);
	press(root, 1, 1);
	assert texts(root) === "<p>x:1</p> <p>y:2</p> ", "x mounted after y: " + texts(root);
	refreshTemplate0(thisFile(), "Late#template", lateTemplateV2, edited, __refreshSetup_Late);
	refreshModule(thisFile());
	assert texts(root) === "<p>x:1</p> <p>y:2</p> ", "each row keeps its own count: " + texts(root);
	dispose();
}

test "refresh state: a template registered at another capture type remounts its component" {
	refreshReset();
	const [root, dispose] = mount(List());
	press(root, 0, 3);
	refreshTemplate(thisFile(), "Row#template", __refreshTmpl_RowWithStep, edited, __refreshSetup_RowWithStep);
	const summary = refreshModule(thisFile());
	assert summary.remounted === 2, "the rows remount: " + summary.remounted.toString();
	assert texts(root) === "<p>a:3</p> <p>b:0</p> ", "and keep their counts: " + texts(root);
	dispose();
}

test "refresh state: state a helper keeps by hand survives a template rebuild, one cell per call" {
	refreshReset();
	const [root, dispose] = mount(Board());
	press(root, 0, 2);
	press(root, 1, 5);
	assert texts(root) === "<p>p=2</p> <p>q=5</p> ", texts(root);
	refreshTemplate0(thisFile(), "Board#template", boardTemplateV2, edited, __refreshSetup_Board);
	refreshModule(thisFile());
	assert all(root, "h1").length === 1, "the new template is mounted";
	assert texts(root) === "<p>p=2</p> <p>q=5</p> ", "both cells kept: " + texts(root);
	dispose();
}

test "refresh state: state kept under a template survives its component's setup edit" {
	refreshReset();
	const [root, dispose] = mount(Board());
	press(root, 0, 2);
	press(root, 1, 5);
	refreshComponent0(thisFile(), "Board|", boardBodyV2, edited);
	const summary = refreshModule(thisFile());
	assert summary.remounted === 1, "the board remounts: " + summary.remounted.toString();
	assert texts(root) === "<p>p=2</p> <p>q=5</p> ", "both cells kept: " + texts(root);
	dispose();
}
