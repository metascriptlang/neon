import { el, text, dynText, NeonNode } from "../../src/render/node";
import { MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Host, HostNode } from "../../src/render/hostTypes";
import { For, ForKeyedBy, ForUnkeyed, Repeat, Show } from "../../src/macros/ui/flow";
import { createSignal, accessor, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { createComponent } from "../../src/render/component";
import { createRoot } from "../../src/core/owner";

function listText(node: MockNode): string {
	let s = "";
	for (const c of node.children) {
		if (c.tag !== "") {
			for (const t of c.children) { s = s + t.text; }
		}
	}
	return s;
}

test "For reactive list reuses rows on reorder, creates only new" {
	const [items, setItems] = createSignal<number[]>([1, 2, 3]);
	let creates = 0;
	const ul = el("ul", [], [], For<number>({
		each: items,
		children: (item, i) => { creates = creates + 1; return <li>{"" + item}</li>; },
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	assert listText(ulNode) === "123", "initial";
	assert creates === 3, "3 rows created";
	setItems([3, 1, 2]);
	assert listText(ulNode) === "312", "reordered";
	assert creates === 3, "no new creates on reorder";
	setItems([3, 1, 2, 4]);
	assert listText(ulNode) === "3124", "append";
	assert creates === 4, "one create for new item";
	setItems([2]);
	assert listText(ulNode) === "2", "shrink";
	assert creates === 4, "no creates on removal";
	d();
}

// PARKED: both fallback cells take the call form because a JSX value in an attribute of a generic
// tag never lowers — `<For each={xs} fallback={<li/>}>` is refused. Card:
// ~/metascript/.inbox/compiler/2026-09-19-jsx-converter-skipped-in-generic-call-inside-macro-arg.md
test "For fallback shows when empty" {
	const [items, setItems] = createSignal<number[]>([1]);
	const ul = el("ul", [], [], For<number>({
		each: items,
		children: (item, i) => <li>{"" + item}</li>,
		fallback: <li>empty</li>,
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	assert listText(ulNode) === "1", "has item";
	setItems([]);
	assert listText(ulNode) === "empty", "fallback shown";
	setItems([5]);
	assert listText(ulNode) === "5", "back to item";
	d();
}

test "Show swaps child/fallback and stays stable while true" {
	const [n, setN] = createSignal(1);
	const div = el("div", [], [], Show({
		when: accessor(() => n() > 0),
		children: <span>on</span>,
		fallback: <span>off</span>,
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(div, host, root);
	const divNode = (root as unknown as MockNode).children[0];

	assert divNode.children[0].children[0].text === "on", "initial on";
	const firstSpan = divNode.children[0];
	setN(2);
	assert divNode.children[0].children[0].text === "on", "still on";
	assert divNode.children[0] === firstSpan, "same node — not rebuilt while truthy";
	setN(0);
	assert divNode.children[0].children[0].text === "off", "fallback off";
	setN(5);
	assert divNode.children[0].children[0].text === "on", "on again";
	d();
}

test "For fallback reactive scope is disposed when rows return" {
	const [items, setItems] = createSignal<number[]>([]);
	const [label, setLabel] = createSignal("empty");
	let fbRuns = 0;
	const fbTick = (): string => { fbRuns = fbRuns + 1; return label(); };
	const ul = el("ul", [], [], For<number>({
		each: items,
		children: (item, i) => <li>{"" + item}</li>,
		fallback: <li>{fbTick()}</li>,
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	assert fbRuns === 1, "fallback effect ran once when empty";
	setLabel("none");
	assert fbRuns === 2, "fallback effect reactive while shown";
	setItems([1]);
	setLabel("ignored");
	assert fbRuns === 2, "fallback effect disposed once rows returned";
	d();
}

test "For fallback reactive scope is disposed with the list" {
	const [label, setLabel] = createSignal("empty");
	let fbRuns = 0;
	const fbTick = (): string => { fbRuns = fbRuns + 1; return label(); };
	createRoot((d) => {
		const [items, setItems] = createSignal<number[]>([]);
		const ul = el("ul", [], [], For<number>({
			each: items,
			children: (item, i) => <li>{"" + item}</li>,
			fallback: <li>{fbTick()}</li>,
		}));
		const host = mockHost();
		const root = host.createElement("root");
		const unmount = render(ul, host, root);
		assert fbRuns === 1, "fallback effect ran once when empty";
		unmount();
		d();
	});
	setLabel("after");
	assert fbRuns === 1, "fallback effect disposed with the list that showed it";
}

test "an accessor feeds For.each directly and the row index is an Accessor" {
	const [items, setItems] = createSignal<number[]>([7, 8]);
	const ul = el("ul", [], [], For<number>({
		each: items,
		children: (item, i) => {
			const idx: Accessor<number> = i;
			return <li>{"" + item + "@" + idx()}</li>;
		},
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	assert listText(ulNode) === "7@08@1", "initial";
	setItems([8, 7]);
	assert listText(ulNode) === "8@07@1", "reordered rows keep live indexes";
	d();
}

function mountedText(view: NeonNode): [() => string, () => void] {
	const host = mockHost();
	const root = host.createElement("root");
	const dispose = render(view, host, root);
	return [() => mockToString(root as unknown as MockNode), dispose];
}

test "a && <X/> child lowers to Show" {
	const [on, setOn] = createSignal(true);
	const [lowered, d1] = mountedText(element(<div>{on && <span>yes</span>}</div>));
	const [explicit, d2] = mountedText(element(<div><Show when={on()}><span>yes</span></Show></div>));
	assert lowered() === explicit(), "initial: lowered=" + lowered() + " explicit=" + explicit();
	assert lowered().indexOf("yes") >= 0, "child shown while true";
	setOn(false);
	assert lowered() === explicit(), "after off: lowered=" + lowered() + " explicit=" + explicit();
	assert lowered().indexOf("yes") < 0, "child gone while false";
	setOn(true);
	assert lowered() === explicit(), "after on: lowered=" + lowered() + " explicit=" + explicit();
	d1(); d2();
}

test "c ? <A/> : <B/> child lowers to Show with a fallback" {
	const [on, setOn] = createSignal(true);
	const [lowered, d1] = mountedText(element(<div>{on ? <span>yes</span> : <b>no</b>}</div>));
	const [explicit, d2] = mountedText(element(<div><Show when={on()} fallback={<b>no</b>}><span>yes</span></Show></div>));
	assert lowered() === explicit(), "initial: lowered=" + lowered() + " explicit=" + explicit();
	assert lowered().indexOf("yes") >= 0, "consequent shown while true";
	setOn(false);
	assert lowered() === explicit(), "after off: lowered=" + lowered() + " explicit=" + explicit();
	assert lowered().indexOf("no") >= 0, "alternate shown while false";
	d1(); d2();
}

test "a ternary with a null arm lowers to Show without a fallback, either way round" {
	const [on, setOn] = createSignal(true);
	const [nullElse, d1] = mountedText(element(<div>{on ? <span>yes</span> : null}</div>));
	const [nullThen, d2] = mountedText(element(<div>{on ? null : <span>yes</span>}</div>));
	const [explicit, d3] = mountedText(element(<div><Show when={on()}><span>yes</span></Show></div>));
	assert nullElse() === explicit(), "null-else initial: " + nullElse() + " vs " + explicit();
	assert nullThen().indexOf("yes") < 0, "null-then hides while true: " + nullThen();
	setOn(false);
	assert nullElse() === explicit(), "null-else after off: " + nullElse() + " vs " + explicit();
	assert nullThen().indexOf("yes") >= 0, "null-then shows while false: " + nullThen();
	d1(); d2(); d3();
}

test "xs.map(row) child lowers to For" {
	const [items, setItems] = createSignal<number[]>([1, 2, 3]);
	const [lowered, d1] = mountedText(element(<ul>{items.map((n: number): NeonNode => element(<li>{n.toString()}</li>))}</ul>));
	const [explicit, d2] = mountedText(element(<ul><For each={items()}>{(n: number, i: Accessor<number>): NeonNode => element(<li>{n.toString()}</li>)}</For></ul>));
	assert lowered() === explicit(), "initial: lowered=" + lowered() + " explicit=" + explicit();
	assert lowered().indexOf("3") >= 0, "rows rendered";
	setItems([3, 1, 2, 4]);
	assert lowered() === explicit(), "after reorder+append: lowered=" + lowered() + " explicit=" + explicit();
	setItems([]);
	assert lowered() === explicit(), "after clear: lowered=" + lowered() + " explicit=" + explicit();
	d1(); d2();
}

function namedRow(s: string, i: Accessor<number>): NeonNode {
	return element(<li>{s + i.toString()}</li>);
}

test "For takes a named row function as its child" {
	const [items, setItems] = createSignal<string[]>(["a", "b"]);
	const [named, d1] = mountedText(element(<ul><For each={items()}>{namedRow}</For></ul>));
	const [arrow, d2] = mountedText(element(<ul><For each={items()}>{(s: string, i: Accessor<number>): NeonNode => element(<li>{s + i.toString()}</li>)}</For></ul>));
	assert named() === arrow(), "initial: named=" + named() + " arrow=" + arrow();
	assert named().indexOf("a0") >= 0 && named().indexOf("b1") >= 0, "indexed rows: " + named();
	setItems(["b", "a", "c"]);
	assert named() === arrow(), "after reorder+append: named=" + named() + " arrow=" + arrow();
	assert named().indexOf("b0") >= 0 && named().indexOf("c2") >= 0, "indexes follow: " + named();
	d1(); d2();
}

function orNone(maybe: NeonNode | null): NeonNode {
	return element(<div>{maybe ?? <i>none</i>}</div>);
}

function orPair(maybe: NeonNode | null): NeonNode {
	return element(<div>{maybe ?? <><p>a</p><p>b</p></>}<i>tail</i></div>);
}

test "a ?? <X/> child mounts the node when present and the JSX arm when null" {
	const [none, d1] = mountedText(orNone(null));
	assert none() === "<root><div><i>none</i></div></root>", "null: " + none();
	const [some, d2] = mountedText(orNone(element(<b>x</b>)));
	assert some() === "<root><div><b>x</b></div></root>", "present: " + some();
	const [pair, d3] = mountedText(orPair(null));
	assert pair() === "<root><div><p>a</p><p>b</p><i>tail</i></div></root>", "fragment arm: " + pair();
	d1(); d2(); d3();
}

test "Show mounts its branch untracked" {
	const [on, setOn] = createSignal(true);
	const [n, setN] = createSignal(0);
	let builds = 0;
	const child: NeonNode = (h: Host, p: HostNode, b: HostNode | null): void => {
		builds = builds + 1;
		const label = n().toString();
		const built: NeonNode = <span>{label}</span>;
		built(h, p, b);
	};
	const div = el("div", [], [], Show({ when: on, children: child }));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(div, host, root);
	assert builds === 1, "branch built once on mount";
	setN(5);
	assert builds === 1, "a signal read while mounting does not rebuild the branch";
	setOn(false);
	setOn(true);
	assert builds === 2, "flipping the condition still rebuilds";
	d();
}

test "Show mounts its fallback untracked" {
	const [on, setOn] = createSignal(false);
	const [n, setN] = createSignal(0);
	let builds = 0;
	const fb: NeonNode = (h: Host, p: HostNode, b: HostNode | null): void => {
		builds = builds + 1;
		const label = n().toString();
		const built: NeonNode = <i>{label}</i>;
		built(h, p, b);
	};
	const div = el("div", [], [], Show({ when: on, children: <span>on</span>, fallback: fb }));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(div, host, root);
	assert builds === 1, "fallback built once on mount";
	setN(5);
	assert builds === 1, "a signal read while mounting does not rebuild the fallback";
	setOn(true);
	setOn(false);
	assert builds === 2, "flipping the condition still rebuilds the fallback";
	d();
}

interface Keyed {
	id: number;
	label: string;
}

function keyedRow(r: Accessor<Keyed>, i: Accessor<number>): NeonNode {
	return element(<li>{r().label}</li>);
}

function keyOf(r: Keyed): number {
	return r.id;
}

test "ForKeyedBy reuses rows across fresh objects that carry the same keys and shows their new items" {
	const [rows, setRows] = createSignal<Keyed[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
	let builds = 0;
	const ul = el("ul", [], [], ForKeyedBy<Keyed, number>({
		each: rows,
		keyed: keyOf,
		children: (r, i) => { builds = builds + 1; return <li>{r().label}</li>; },
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	assert listText(ulNode) === "ab", "both rows rendered: " + listText(ulNode);
	assert builds === 2, "two rows built";
	setRows([{ id: 2, label: "b2" }, { id: 1, label: "a2" }]);
	assert builds === 2, "a reorder of fresh objects with the same keys builds nothing";
	assert listText(ulNode) === "b2a2", "the rows moved and show their new items: " + listText(ulNode);
	d();
}

test "ForKeyedBy inserts and removes by key and keeps the index accessor live" {
	const [rows, setRows] = createSignal<Keyed[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
	let builds = 0;
	const ul = el("ul", [], [], ForKeyedBy<Keyed, number>({
		each: rows,
		keyed: keyOf,
		children: (r, i) => { builds = builds + 1; return <li>{r().label + i().toString()}</li>; },
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	assert builds === 2, "two rows built";
	setRows([{ id: 3, label: "c" }, { id: 1, label: "a" }, { id: 2, label: "b" }]);
	assert builds === 3, "one build for the inserted key";
	assert listText(ulNode) === "c0a1b2", "indexes follow the move: " + listText(ulNode);
	setRows([{ id: 2, label: "b" }]);
	assert builds === 3, "removal builds nothing";
	assert listText(ulNode) === "b0", "only the survivor is left: " + listText(ulNode);
	d();
}

test "ForKeyedBy takes a string key and pairs rows sharing a key by occurrence" {
	const [rows, setRows] = createSignal<Keyed[]>([{ id: 1, label: "a" }, { id: 1, label: "b" }]);
	let builds = 0;
	const ul = el("ul", [], [], ForKeyedBy<Keyed, string>({
		each: rows,
		keyed: (r: Keyed): string => "k" + r.id.toString(),
		children: (r, i) => { builds = builds + 1; return <li>{r().label}</li>; },
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	assert listText(ulNode) === "ab" && builds === 2, "a shared key mounts both rows: " + listText(ulNode);
	setRows([{ id: 1, label: "b2" }]);
	assert listText(ulNode) === "b2" && builds === 2, "the first row of the key stays and shows the new item: " + listText(ulNode);
	d();
}

test "ForKeyedBy takes a fallback" {
	const [rows, setRows] = createSignal<Keyed[]>([]);
	const ul = el("ul", [], [], ForKeyedBy<Keyed, number>({
		each: rows,
		keyed: keyOf,
		children: keyedRow,
		fallback: <li>empty</li>,
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	assert listText(ulNode) === "empty", "the fallback shows while the list is empty";
	setRows([{ id: 4, label: "d" }]);
	assert listText(ulNode) === "d", "the keyed row replaces the fallback";
	setRows([]);
	assert listText(ulNode) === "empty", "the fallback comes back";
	d();
}

test "For gives a row that names its index a live index through the tag" {
	const [items, setItems] = createSignal<string[]>(["a", "b"]);
	const [view, d] = mountedText(element(<ul><For each={items()}>{(s: string, i: Accessor<number>): NeonNode => element(<li>{s + i().toString()}</li>)}</For></ul>));
	assert view().indexOf("a0") >= 0 && view().indexOf("b1") >= 0, "indexed rows: " + view();
	setItems(["b", "a"]);
	assert view().indexOf("b0") >= 0 && view().indexOf("a1") >= 0, "indexes follow the reorder: " + view();
	d();
}

test "For renders a row that never names its index" {
	const [items, setItems] = createSignal<string[]>(["a", "b"]);
	const [view, d] = mountedText(element(<ul><For each={items()}>{(s: string, i: Accessor<number>): NeonNode => element(<li>{s}</li>)}</For></ul>));
	assert view().indexOf("a") >= 0 && view().indexOf("b") >= 0, "rows render: " + view();
	setItems(["b", "a", "c"]);
	assert view().indexOf("c") >= 0, "reorder and append still work: " + view();
	d();
}

test "map.ts:330 For keeps the index live wherever the row names it" {
	const [items, setItems] = createSignal<string[]>(["a", "b"]);
	const [view, d] = mountedText(element(
		<ul>
			<For each={items()}>{(s: string, i: Accessor<number>): NeonNode => element(<li title={i().toString()}>{`${s}${i()}`}</li>)}</For>
		</ul>
	));
	assert view() === "<root><ul><li title=\"0\">a0</li><li title=\"1\">b1</li></ul></root>", "initial: " + view();
	setItems(["b", "a"]);
	assert view() === "<root><ul><li title=\"0\">b0</li><li title=\"1\">a1</li></ul></root>", "attribute and template literal follow the reorder: " + view();
	d();
}

test "map.ts:97 For keyed by a function keeps the index live when the row reads it and renders when it does not" {
	const [rows, setRows] = createSignal<Keyed[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
	const key = (r: Keyed): number => r.id;
	const [withIndex, d1] = mountedText(element(<ul><For each={rows()} keyed={key}>{(r: Accessor<Keyed>, i: Accessor<number>): NeonNode => element(<li>{r().label + i().toString()}</li>)}</For></ul>));
	const [without, d2] = mountedText(element(<ul><For each={rows()} keyed={key}>{(r: Accessor<Keyed>, i: Accessor<number>): NeonNode => element(<li>{r().label}</li>)}</For></ul>));
	assert withIndex() === "<root><ul><li>a0</li><li>b1</li></ul></root>", "indexed: " + withIndex();
	assert without() === "<root><ul><li>a</li><li>b</li></ul></root>", "plain: " + without();
	setRows([{ id: 2, label: "b2" }, { id: 3, label: "c" }, { id: 1, label: "a2" }]);
	assert withIndex() === "<root><ul><li>b20</li><li>c1</li><li>a22</li></ul></root>", "indexes follow insert and move: " + withIndex();
	assert without() === "<root><ul><li>b2</li><li>c</li><li>a2</li></ul></root>", "rows follow insert and move: " + without();
	setRows([]);
	assert without() === "<root><ul></ul></root>", "emptied: " + without();
	d1();
	d2();
}

test "map.ts:75 a row that reads its index after usesIndex={false} was written on the tag raises at mount" {
	const [items, _s] = createSignal<string[]>(["a"]);
	let caught = "";
	try {
		mountedText(element(<ul><For each={items()} usesIndex={false}>{labelFromIndex}</For></ul>));
	} catch (e) {
		caught = e.toString();
	}
	assert caught.includes("no index accessor"), "the engine names the missing index: " + caught;
}

let flowBuilds = 0;

function labelAndIndexRow(r: Accessor<Keyed>, i: Accessor<number>): NeonNode {
	flowBuilds = flowBuilds + 1;
	return element(<li>{r().label + i().toString()}</li>);
}

function countedRow(x: string, i: Accessor<number>): NeonNode {
	flowBuilds = flowBuilds + 1;
	return element(<li>{x}</li>);
}

function labelFromIndex(x: string, i: Accessor<number>): NeonNode {
	return element(<li>{x + i().toString()}</li>);
}

function plainRow(x: string, i: Accessor<number>): NeonNode {
	return element(<li>{x}</li>);
}

function positionRow(x: Accessor<string>, i: number): NeonNode {
	flowBuilds = flowBuilds + 1;
	return element(<li>{x() + i.toString()}</li>);
}

function countedIndexRow(i: number): NeonNode {
	flowBuilds = flowBuilds + 1;
	return element(<li>{i.toString()}</li>);
}

test "BUGS.md <For key>: a keyed row shows the new item when the key stays, through the tag" {
	const [rows, setRows] = createSignal<Keyed[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
	const [view, d] = mountedText(element(<ul><For each={rows()} keyed={(r: Keyed): number => r.id}>{keyedRow}</For></ul>));
	assert view() === "<root><ul><li>a</li><li>b</li></ul></root>", "initial: " + view();
	setRows([{ id: 2, label: "b2" }, { id: 1, label: "a2" }]);
	assert view() === "<root><ul><li>b2</li><li>a2</li></ul></root>", "reordered with the new items: " + view();
	d();
}

test "For keyed with a string key and a row that reads the index accessor, through the tag" {
	const [rows, setRows] = createSignal<Keyed[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
	flowBuilds = 0;
	const [view, d] = mountedText(element(
		<ul><For each={rows()} keyed={(r: Keyed): string => "k" + r.id.toString()}>{labelAndIndexRow}</For></ul>
	));
	assert view() === "<root><ul><li>a0</li><li>b1</li></ul></root>", "initial: " + view();
	setRows([{ id: 3, label: "c" }, { id: 2, label: "b2" }, { id: 1, label: "a2" }]);
	assert view() === "<root><ul><li>c0</li><li>b21</li><li>a22</li></ul></root>", "insert, move and new items: " + view();
	assert flowBuilds === 3, "only the inserted key built a row: " + flowBuilds.toString();
	d();
}

test "For keyed={true} and a bare keyed are the default identity mode, through the tag" {
	const [xs, setXs] = createSignal<string[]>(["a", "b"]);
	flowBuilds = 0;
	const [explicit, d1] = mountedText(element(<ul><For each={xs()} keyed={true}>{countedRow}</For></ul>));
	const [bare, d2] = mountedText(element(<ul><For each={xs()} keyed>{plainRow}</For></ul>));
	setXs(["b", "a"]);
	assert explicit() === "<root><ul><li>b</li><li>a</li></ul></root>" && bare() === explicit(), "both reorder: " + explicit() + " " + bare();
	assert flowBuilds === 2, "identity rows are reused on a reorder: " + flowBuilds.toString();
	d1(); d2();
}

test "For keyed={false} keeps rows per position and shows the new value in place, through the tag" {
	const [xs, setXs] = createSignal<string[]>(["a", "b"]);
	flowBuilds = 0;
	const [view, d] = mountedText(element(<ul><For each={xs()} keyed={false}>{positionRow}</For></ul>));
	assert view() === "<root><ul><li>a0</li><li>b1</li></ul></root>", "initial: " + view();
	setXs(["b", "a", "c"]);
	assert view() === "<root><ul><li>b0</li><li>a1</li><li>c2</li></ul></root>", "values changed in place, one row appended: " + view();
	assert flowBuilds === 3, "no row rebuilt: " + flowBuilds.toString();
	setXs(["z"]);
	assert view() === "<root><ul><li>z0</li></ul></root>", "shrink: " + view();
	d();
}

const abcd: string[] = ["a", "b", "c", "d"];

function reorderings(): string[][] {
	return [
		["b", "c", "d"], ["a", "c", "d"], ["a", "b", "d"], ["a", "b", "c"],
		["c", "d"], ["b", "d"], ["b", "c"], ["a", "d"], ["a", "c"], ["a", "b"],
		["a"], ["b"], ["c"], ["d"], [],
		["b", "a", "c", "d"], ["c", "b", "a", "d"], ["d", "b", "c", "a"],
		["b", "c", "d", "a"], ["c", "d", "a", "b"], ["d", "a", "b", "c"],
		["d", "c", "b", "a"],
		["e", "f", "g", "h"],
		["a", "b", "c", "d", "e", "f"],
		["x", "a", "y", "b", "z"],
		["milk", "bread", "chips", "cookie", "honey"], ["chips", "bread", "cookie", "milk", "honey"],
	];
}

function rowsBefore(xs: string[], tail: string): string {
	let out = "";
	for (const x of xs) { out = out + "<li>" + x + "</li>"; }
	return "<root><ul>" + out + tail + "</ul></root>";
}

test "for.nonkeyed.spec.tsx:99 For keyed={false} renders every removal, swap, rotation and replacement before a sibling" {
	const [xs, setXs] = createSignal<string[]>(abcd);
	const [view, d] = mountedText(element(<ul><For each={xs()} keyed={false}>{(x: Accessor<string>, i: number): NeonNode => element(<li>{x()}</li>)}</For><b>z</b></ul>));
	assert view() === rowsBefore(abcd, "<b>z</b>"), "initial: " + view();
	for (const c of reorderings()) {
		setXs(c);
		assert view() === rowsBefore(c, "<b>z</b>"), "after " + c.join(",") + ": " + view();
		setXs(abcd);
		assert view() === rowsBefore(abcd, "<b>z</b>"), "back to abcd after " + c.join(",") + ": " + view();
	}
	d();
}

test "for.nonkeyed.spec.tsx:99 For (identity) renders every removal, swap, rotation and replacement before a sibling" {
	const [xs, setXs] = createSignal<string[]>(abcd);
	const [view, d] = mountedText(element(<ul><For each={xs()}>{(x: string, i: Accessor<number>): NeonNode => element(<li>{x}</li>)}</For><b>z</b></ul>));
	assert view() === rowsBefore(abcd, "<b>z</b>"), "initial: " + view();
	for (const c of reorderings()) {
		setXs(c);
		assert view() === rowsBefore(c, "<b>z</b>"), "after " + c.join(",") + ": " + view();
		setXs(abcd);
		assert view() === rowsBefore(abcd, "<b>z</b>"), "back to abcd after " + c.join(",") + ": " + view();
	}
	d();
}

test "for.nonkeyed.spec.tsx:99 For keyed by a function renders every removal, swap, rotation and replacement before a sibling" {
	const [xs, setXs] = createSignal<string[]>(abcd);
	const [view, d] = mountedText(element(<ul><For each={xs()} keyed={(x: string): string => x}>{(x: Accessor<string>, i: Accessor<number>): NeonNode => element(<li>{x()}</li>)}</For><b>z</b></ul>));
	assert view() === rowsBefore(abcd, "<b>z</b>"), "initial: " + view();
	for (const c of reorderings()) {
		setXs(c);
		assert view() === rowsBefore(c, "<b>z</b>"), "after " + c.join(",") + ": " + view();
		setXs(abcd);
		assert view() === rowsBefore(abcd, "<b>z</b>"), "back to abcd after " + c.join(",") + ": " + view();
	}
	d();
}

test "For keyed={false} fallback shows on empty and yields to rows, through the tag" {
	const [xs, setXs] = createSignal<string[]>([]);
	const [view, d] = mountedText(element(<ul><For each={xs()} keyed={false} fallback={<li>none</li>}>{(x: Accessor<string>, i: number): NeonNode => element(<li>{x()}</li>)}</For></ul>));
	assert view() === "<root><ul><li>none</li></ul></root>", "empty: " + view();
	setXs(["a"]);
	assert view() === "<root><ul><li>a</li></ul></root>", "rows: " + view();
	setXs([]);
	assert view() === "<root><ul><li>none</li></ul></root>", "empty again: " + view();
	d();
}

function repeatRow(i: number): NeonNode {
	return element(<li>{i.toString()}</li>);
}

test "Repeat renders one row per index and keeps its rows when only the count changes" {
	const [n, setN] = createSignal<number>(2);
	flowBuilds = 0;
	const [view, d] = mountedText(element(<ul><Repeat count={n()}>{countedIndexRow}</Repeat></ul>));
	assert view() === "<root><ul><li>0</li><li>1</li></ul></root>", "initial: " + view();
	setN(4);
	assert view() === "<root><ul><li>0</li><li>1</li><li>2</li><li>3</li></ul></root>", "grown: " + view();
	assert flowBuilds === 4, "the first two rows were kept: " + flowBuilds.toString();
	setN(1);
	assert view() === "<root><ul><li>0</li></ul></root>", "shrunk: " + view();
	assert flowBuilds === 4, "shrinking builds nothing: " + flowBuilds.toString();
	d();
}

test "Repeat takes a named row, a from offset that slides the window, and keeps the overlap" {
	const [start, setStart] = createSignal<number>(1);
	const [view, d] = mountedText(element(<ul><Repeat count={3} from={start()}>{repeatRow}</Repeat></ul>));
	assert view() === "<root><ul><li>1</li><li>2</li><li>3</li></ul></root>", "window 1..3: " + view();
	setStart(3);
	assert view() === "<root><ul><li>3</li><li>4</li><li>5</li></ul></root>", "window 3..5: " + view();
	setStart(0);
	assert view() === "<root><ul><li>0</li><li>1</li><li>2</li></ul></root>", "backward disjoint jump: " + view();
	d();
}

test "Repeat fallback shows when the count is 0 and yields to rows" {
	const [n, setN] = createSignal<number>(0);
	const [view, d] = mountedText(element(<ul><Repeat count={n()} fallback={<li>none</li>}>{repeatRow}</Repeat></ul>));
	assert view() === "<root><ul><li>none</li></ul></root>", "empty: " + view();
	setN(2);
	assert view() === "<root><ul><li>0</li><li>1</li></ul></root>", "rows: " + view();
	setN(0);
	assert view() === "<root><ul><li>none</li></ul></root>", "empty again: " + view();
	d();
}

test "Repeat refuses a fractional count through the tag" {
	const [n, setN] = createSignal<number>(1.5);
	let caught = "";
	try {
		const [view, d] = mountedText(element(<ul><Repeat count={n()}>{repeatRow}</Repeat></ul>));
		view();
		d();
	} catch (e) { caught = e.toString(); }
	assert caught.includes("Repeat: count"), "the count is named: " + caught;
}

test "map.ts:88 For: a binding inside a row keeps following its own signal through a reorder, an insert and a removal" {
	const [xs, setXs] = createSignal<string[]>(["a", "b"]);
	const [tag, setTag] = createSignal<string>("!");
	const [view, d] = mountedText(element(<ul><For each={xs()}>{(s: string, i: Accessor<number>): NeonNode => element(<li>{s + tag()}</li>)}</For></ul>));
	assert view() === "<root><ul><li>a!</li><li>b!</li></ul></root>", "initial: " + view();
	setXs(["b", "a"]);
	setTag("?");
	assert view() === "<root><ul><li>b?</li><li>a?</li></ul></root>", "rows that moved follow the signal: " + view();
	setXs(["c", "b", "a"]);
	setTag("#");
	assert view() === "<root><ul><li>c#</li><li>b#</li><li>a#</li></ul></root>", "rows that stayed and the row that came follow it: " + view();
	setXs(["a"]);
	setTag("%");
	assert view() === "<root><ul><li>a%</li></ul></root>", "the row left after a removal follows it: " + view();
	d();
}

test "map.ts:88 ForKeyedBy: a binding inside a row keeps following its own signal through a reorder, an insert and a removal" {
	const [rows, setRows] = createSignal<Keyed[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
	const [tag, setTag] = createSignal<string>("!");
	const key = (r: Keyed): number => r.id;
	const [view, d] = mountedText(element(<ul><For each={rows()} keyed={key}>{(r: Accessor<Keyed>, i: Accessor<number>): NeonNode => element(<li>{r().label + tag()}</li>)}</For></ul>));
	assert view() === "<root><ul><li>a!</li><li>b!</li></ul></root>", "initial: " + view();
	setRows([{ id: 2, label: "B" }, { id: 1, label: "A" }]);
	setTag("?");
	assert view() === "<root><ul><li>B?</li><li>A?</li></ul></root>", "rows that moved follow the signal: " + view();
	setRows([{ id: 3, label: "c" }, { id: 2, label: "B" }, { id: 1, label: "A" }]);
	setTag("#");
	assert view() === "<root><ul><li>c#</li><li>B#</li><li>A#</li></ul></root>", "rows that stayed and the row that came follow it: " + view();
	setRows([{ id: 1, label: "A" }]);
	setTag("%");
	assert view() === "<root><ul><li>A%</li></ul></root>", "the row left after a removal follows it: " + view();
	d();
}

test "map.ts:88 For keyed={false}: a binding inside a row keeps following its own signal through a reorder, an insert and a removal" {
	const [xs, setXs] = createSignal<string[]>(["a", "b"]);
	const [tag, setTag] = createSignal<string>("!");
	const [view, d] = mountedText(element(<ul><For each={xs()} keyed={false}>{(x: Accessor<string>, i: number): NeonNode => element(<li>{x() + tag()}</li>)}</For></ul>));
	assert view() === "<root><ul><li>a!</li><li>b!</li></ul></root>", "initial: " + view();
	setXs(["b", "a"]);
	setTag("?");
	assert view() === "<root><ul><li>b?</li><li>a?</li></ul></root>", "rows that changed value follow the signal: " + view();
	setXs(["c", "b", "a"]);
	setTag("#");
	assert view() === "<root><ul><li>c#</li><li>b#</li><li>a#</li></ul></root>", "rows that stayed and the row that came follow it: " + view();
	setXs(["a"]);
	setTag("%");
	assert view() === "<root><ul><li>a%</li></ul></root>", "the row left after a removal follows it: " + view();
	d();
}

test "map.ts:624 Repeat: a binding inside a row keeps following its own signal through a grow and a shrink" {
	const [n, setN] = createSignal<number>(2);
	const [tag, setTag] = createSignal<string>("!");
	const [view, d] = mountedText(element(<ul><Repeat count={n()}>{(i: number): NeonNode => element(<li>{i.toString() + tag()}</li>)}</Repeat></ul>));
	assert view() === "<root><ul><li>0!</li><li>1!</li></ul></root>", "initial: " + view();
	setN(4);
	setTag("?");
	assert view() === "<root><ul><li>0?</li><li>1?</li><li>2?</li><li>3?</li></ul></root>", "kept and new rows follow the signal: " + view();
	setN(1);
	setTag("#");
	assert view() === "<root><ul><li>0#</li></ul></root>", "the row left after a shrink follows it: " + view();
	d();
}
