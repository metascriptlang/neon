import { NeonNode } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { MockNode, HostNode, mockHost, render, mockToString } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View, Text } from "../../src/components/primitives";
import { createSignal, Accessor } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { For, Show } from "../../src/macros/ui/flow";

function Pair(props: { label: Accessor<string> }): NeonNode {
	return element(<><p>r1</p><p>r2</p></>);
}

test "a fragment child flattens into its parent" {
	const v: NeonNode = element(<div><><p>a</p><p>b</p></></div>);
	assert renderToString(v) === "<div><p>a</p><p>b</p></div>", "no wrapper node";
}

test "nested fragments flatten all the way" {
	const v: NeonNode = element(<div><><p>a</p><><p>b</p><p>c</p></></></div>);
	assert renderToString(v) === "<div><p>a</p><p>b</p><p>c</p></div>", "one flat child list";
}

test "a top-level fragment renders every root" {
	const v: NeonNode = element(<><p>a</p><p>b</p></>);
	assert renderToString(v) === "<p>a</p><p>b</p>", "multi-root";
}

test "a top-level fragment mounts as siblings under one parent" {
	const host = mockHost();
	const root = host.createElement("root");
	render(element(<><p>a</p><p>b</p></>), host, root);
	const r = root as unknown as MockNode;
	assert r.children.length === 2, "two roots appended";
	assert mockToString(r.children[0]) === "<p>a</p>", "first root";
	assert mockToString(r.children[1]) === "<p>b</p>", "second root";
}

test "a fragment flattens inside a component tag too" {
	const v: NeonNode = element(<View><><Text>a</Text><Text>b</Text></></View>);
	assert renderToString(v) === "<div><span>a</span><span>b</span></div>", "component children list stays flat";
}

test "a component may return a fragment" {
	const v: NeonNode = element(<div><Pair label="x" /></div>);
	assert renderToString(v) === "<div><p>r1</p><p>r2</p></div>", "server render";
	const host = mockHost();
	const root = host.createElement("root");
	render(element(<div><Pair label="x" /></div>), host, root);
	assert mockToString((root as unknown as MockNode).children[0]) === "<div><p>r1</p><p>r2</p></div>", "mount";
}

test "a top-level fragment keeps its children reactive" {
	createRoot((d) => {
		const [n, setN] = createSignal(1);
		const host = mockHost();
		const root = host.createElement("root");
		render(element(<><p>{n() + ""}</p><span>fixed</span></>), host, root);
		const r = root as unknown as MockNode;
		assert r.children.length === 2, "two roots";
		assert mockToString(r.children[0]) === "<p>1</p>", "initial";
		setN(2);
		assert mockToString(r.children[0]) === "<p>2</p>", "first root still reactive";
		assert r.children.length === 2, "root count unchanged";
		d();
	});
}

test "an empty fragment contributes no child" {
	assert renderToString(element(<div><></></div>)) === "<div></div>", "erased at compile time";
	const host = mockHost();
	const root = host.createElement("root");
	render(element(<div><></></div>), host, root);
	assert (root as unknown as MockNode).children[0].children.length === 0, "no placeholder mounted";
}

test "a bare empty fragment at the root mounts nothing" {
	assert renderToString(element(<></>)) === "", "renders nothing";
	const host = mockHost();
	const root = host.createElement("root");
	render(element(<></>), host, root);
	assert (root as unknown as MockNode).children.length === 0, "no placeholder, matching Solid's empty array";
}

test "a fragment carries text and reactive children" {
	createRoot((d) => {
		const [n, setN] = createSignal(1);
		const host = mockHost();
		const root = host.createElement("root");
		render(element(<div><>hi <p>{n() + ""}</p></></div>), host, root);
		const box = (root as unknown as MockNode).children[0];
		assert mockToString(box) === "<div>hi <p>1</p></div>", "initial";
		setN(2);
		assert mockToString(box) === "<div>hi <p>2</p></div>", "reactive child still updates";
		d();
	});
}

test "a fragment child flattens the same under direct emission" {
	const host = mockHost();
	const treeRoot = host.createElement("root");
	render(element(<div><><p>a</p><p>b</p></></div>), host, treeRoot);
	const directRoot = host.createElement("root");
	const mount = element(<div><><p>a</p><p>b</p></></div>);
	mount(host, directRoot, null);
	const t = mockToString(treeRoot as unknown as MockNode);
	const d = mockToString(directRoot as unknown as MockNode);
	assert t === d, "tree=" + t + " direct=" + d;
}

test "nested fragments flatten the same under direct emission" {
	const host = mockHost();
	const treeRoot = host.createElement("root");
	render(element(<div><><p>a</p><><p>b</p><p>c</p></></></div>), host, treeRoot);
	const directRoot = host.createElement("root");
	const mount = element(<div><><p>a</p><><p>b</p><p>c</p></></></div>);
	mount(host, directRoot, null);
	const t = mockToString(treeRoot as unknown as MockNode);
	const d = mockToString(directRoot as unknown as MockNode);
	assert t === d, "tree=" + t + " direct=" + d;
}

test "an empty fragment is erased under direct emission too" {
	const host = mockHost();
	const directRoot = host.createElement("root");
	const mount = element(<div><></></div>);
	mount(host, directRoot, null);
	assert mockToString(directRoot as unknown as MockNode) === "<root><div></div></root>", "no placeholder";
}

test "a fragment inside a component tag flattens under direct emission" {
	const host = mockHost();
	const treeRoot = host.createElement("root");
	render(element(<View><><Text>a</Text><Text>b</Text></></View>), host, treeRoot);
	const directRoot = host.createElement("root");
	const mount = element(<View><><Text>a</Text><Text>b</Text></></View>);
	mount(host, directRoot, null);
	const t = mockToString(treeRoot as unknown as MockNode);
	const d = mockToString(directRoot as unknown as MockNode);
	assert t === d, "tree=" + t + " direct=" + d;
}

test "a flattened fragment child stays reactive under direct emission" {
	createRoot((dispose) => {
		const [n, setN] = createSignal(1);
		const host = mockHost();
		const treeRoot = host.createElement("root");
		render(element(<div><>hi <p>{n() + ""}</p></></div>), host, treeRoot);
		const directRoot = host.createElement("root");
		const mount = element(<div><>hi <p>{n() + ""}</p></></div>);
		mount(host, directRoot, null);
		assert mockToString(treeRoot as unknown as MockNode) === mockToString(directRoot as unknown as MockNode), "initial";
		setN(2);
		const t = mockToString(treeRoot as unknown as MockNode);
		const d = mockToString(directRoot as unknown as MockNode);
		assert t === d, "after set: tree=" + t + " direct=" + d;
		assert d.indexOf("<p>2</p>") >= 0, "direct spot updated: " + d;
		dispose();
	});
}

test "a component that returns a fragment mounts under direct emission" {
	const host = mockHost();
	const treeRoot = host.createElement("root");
	render(element(<div><Pair label="x" /></div>), host, treeRoot);
	const directRoot = host.createElement("root");
	const mount = element(<div><Pair label="x" /></div>);
	mount(host, directRoot, null);
	const t = mockToString(treeRoot as unknown as MockNode);
	const d = mockToString(directRoot as unknown as MockNode);
	assert t === d, "tree=" + t + " direct=" + d;
	assert d === "<root><div><p>r1</p><p>r2</p></div></root>", "both roots spliced: " + d;
}

function Gate(props: { open: Accessor<boolean> }): NeonNode {
	return <Show when={props.open()}><i>on</i></Show>;
}

test "a fragment row moves and leaves as one span" {
	createRoot((dispose) => {
		const [items, setItems] = createSignal<string[]>(["a", "b", "c"]);
		const host = mockHost();
		const root = host.createElement("root");
		render(<ul><For each={items()}>{(item: string, i: Accessor<number>): NeonNode => <><dt>{item}</dt><dd>{item + "!"}</dd></>}</For></ul>, host, root);
		const first = mockToString(root as unknown as MockNode);
		assert first === "<root><ul><dt>a</dt><dd>a!</dd><dt>b</dt><dd>b!</dd><dt>c</dt><dd>c!</dd></ul></root>", "initial: " + first;
		setItems(["c", "a", "b"]);
		const moved = mockToString(root as unknown as MockNode);
		assert moved === "<root><ul><dt>c</dt><dd>c!</dd><dt>a</dt><dd>a!</dd><dt>b</dt><dd>b!</dd></ul></root>", "reorder: " + moved;
		setItems(["c", "b"]);
		const removed = mockToString(root as unknown as MockNode);
		assert removed === "<root><ul><dt>c</dt><dd>c!</dd><dt>b</dt><dd>b!</dd></ul></root>", "remove: " + removed;
		dispose();
	});
}

test "a row that opens with a closed region still moves with its span" {
	createRoot((dispose) => {
		const [items, setItems] = createSignal<string[]>(["a", "b"]);
		const [open, setOpen] = createSignal(false);
		const host = mockHost();
		const root = host.createElement("root");
		render(<ul><For each={items()}>{(item: string, i: Accessor<number>): NeonNode => <><Gate open={open()} /><li>{item}</li></>}</For></ul>, host, root);
		setItems(["b", "a"]);
		setOpen(true);
		const shown = mockToString(root as unknown as MockNode);
		assert shown === "<root><ul><i>on</i><li>b</li><i>on</i><li>a</li></ul></root>", "each gate opens inside its own row: " + shown;
		dispose();
	});
}

function boxOf(root: HostNode): string {
	return mockToString((root as unknown as MockNode).children[0]);
}

test "a fragment picked by && mounts every root between its siblings and leaves as one span" {
	createRoot((dispose) => {
		const [on, setOn] = createSignal(true);
		const host = mockHost();
		const root = host.createElement("root");
		render(<div><i>head</i>{on() && <><p>a</p><p>b</p></>}<i>tail</i></div>, host, root);
		assert boxOf(root) === "<div><i>head</i><p>a</p><p>b</p><i>tail</i></div>", "initial: " + boxOf(root);
		setOn(false);
		assert boxOf(root) === "<div><i>head</i><i>tail</i></div>", "both roots leave: " + boxOf(root);
		setOn(true);
		assert boxOf(root) === "<div><i>head</i><p>a</p><p>b</p><i>tail</i></div>", "both roots return in place: " + boxOf(root);
		dispose();
	});
}

test "a ternary switches between two fragments" {
	createRoot((dispose) => {
		const [on, setOn] = createSignal(true);
		const host = mockHost();
		const root = host.createElement("root");
		render(<div>{on() ? <><p>a</p><p>b</p></> : <><b>x</b><b>y</b><b>z</b></>}<i>tail</i></div>, host, root);
		assert boxOf(root) === "<div><p>a</p><p>b</p><i>tail</i></div>", "initial: " + boxOf(root);
		setOn(false);
		assert boxOf(root) === "<div><b>x</b><b>y</b><b>z</b><i>tail</i></div>", "other arm: " + boxOf(root);
		setOn(true);
		assert boxOf(root) === "<div><p>a</p><p>b</p><i>tail</i></div>", "back: " + boxOf(root);
		dispose();
	});
}

test "a ternary pairs a fragment with null or with one element, either way round" {
	createRoot((dispose) => {
		const [on, setOn] = createSignal(false);
		const host = mockHost();
		const root = host.createElement("root");
		render(<div>{on() ? <><p>a</p><p>b</p></> : null}|{on() ? null : <><b>x</b><b>y</b></>}|{on() ? <em>one</em> : <><u>m</u><u>n</u></>}</div>, host, root);
		assert boxOf(root) === "<div>|<b>x</b><b>y</b>|<u>m</u><u>n</u></div>", "initial: " + boxOf(root);
		setOn(true);
		assert boxOf(root) === "<div><p>a</p><p>b</p>||<em>one</em></div>", "flipped: " + boxOf(root);
		dispose();
	});
}

test "a fragment inside an expression keeps its own spots and its own conditions live" {
	createRoot((dispose) => {
		const [on, setOn] = createSignal(true);
		const [deep, setDeep] = createSignal(false);
		const [n, setN] = createSignal(1);
		const host = mockHost();
		const root = host.createElement("root");
		render(<div>{on() && <>n=<p>{n() + ""}</p>{deep() && <><s>d1</s><s>d2</s></>}</>}</div>, host, root);
		assert boxOf(root) === "<div>n=<p>1</p></div>", "initial: " + boxOf(root);
		setN(2);
		setDeep(true);
		assert boxOf(root) === "<div>n=<p>2</p><s>d1</s><s>d2</s></div>", "inner spot and inner fragment: " + boxOf(root);
		setOn(false);
		assert boxOf(root) === "<div></div>", "the outer fragment takes the inner one with it: " + boxOf(root);
		dispose();
	});
}

test "a fragment picked by a plain value mounts once" {
	const cond: boolean = true;
	const v: NeonNode = <div>{cond && <><p>a</p><p>b</p></>}</div>;
	assert renderToString(v) === "<div><p>a</p><p>b</p></div>", "static condition: " + renderToString(v);
}

test "a fragment is a fallback" {
	createRoot((dispose) => {
		const [on, setOn] = createSignal(false);
		const host = mockHost();
		const root = host.createElement("root");
		render(<div><Show when={on()} fallback={<><b>x</b><b>y</b></>}><p>a</p></Show></div>, host, root);
		assert boxOf(root) === "<div><b>x</b><b>y</b></div>", "fallback fragment: " + boxOf(root);
		setOn(true);
		assert boxOf(root) === "<div><p>a</p></div>", "children: " + boxOf(root);
		dispose();
	});
}

function passThrough(n: NeonNode): NeonNode { return n; }

test "a fragment handed to a function that takes a NeonNode mounts every root" {
	const v: NeonNode = <div>{passThrough(<><p>a</p><p>b</p></>)}</div>;
	assert renderToString(v) === "<div><p>a</p><p>b</p></div>", "through a call: " + renderToString(v);
}
