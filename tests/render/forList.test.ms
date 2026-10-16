import { el, NeonNode } from "../../src/render/node";
import { MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { ForList } from "../../src/macros/ui/flow";
import { createList } from "../../src/core/list";
import { Accessor } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { onCleanup } from "../../src/core/cleanup";
import { createRenderEffect } from "../../src/core/effect";
import { resetErrorHalt } from "../../src/core/runtime";
import { Cleanup, Dispose } from "../../src/core/types";


function rowText(node: MockNode): string {
	let s = "";
	for (const c of node.children) {
		if (c.tag !== "") {
			for (const t of c.children) { s = s + t.text; }
		}
	}
	return s;
}

function numberRow(item: Accessor<number>): NeonNode {
	return <li>{"" + item()}</li>;
}

interface Keyed {
	id: number;
	label: string;
}

test "ForList is written as a tag" {
	const l = createList<number>([1, 2]);
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(<ul><ForList each={l}>{numberRow}</ForList></ul>, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	assert rowText(ulNode) === "12", "initial: " + rowText(ulNode);
	l.push(3);
	assert rowText(ulNode) === "123", "after push: " + rowText(ulNode);
	d();
}

struct GridRun {
	units: int32;
}

struct GridLine {
	text: string;
	runs: Vec<GridRun>;
	cursorCell: int32;
}

function gridRow(item: Accessor<GridLine>): NeonNode {
	return <li>{item().text + item().runs.length.toString()}</li>;
}

test "ForList mounts one row per item" {
	createRoot((d) => {
		const l = createList<number>([1, 2, 3]);
		const ul = el("ul", [], [], ForList<number>({ each: l, children: numberRow }));
		const host = mockHost();
		const root = host.createElement("root");
		render(ul, host, root);
		const ulNode = (root as unknown as MockNode).children[0];
		assert rowText(ulNode) === "123", "initial: " + rowText(ulNode);
		d();
	});
}

test "push and insert put a row at the slot the op names" {
	const l = createList<number>([1, 2]);
	const ul = el("ul", [], [], ForList<number>({ each: l, children: numberRow }));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	l.push(3);
	assert rowText(ulNode) === "123", "push appends: " + rowText(ulNode);
	l.insert(0, 0);
	assert rowText(ulNode) === "0123", "insert at the head: " + rowText(ulNode);
	l.insert(2, 9);
	assert rowText(ulNode) === "01923", "insert in the middle: " + rowText(ulNode);
	l.insert(5, 4);
	assert rowText(ulNode) === "019234", "insert at the length: " + rowText(ulNode);
	d();
}

test "a row is built once and reused across insert, move and remove" {
	const l = createList<number>([1, 2, 3]);
	let builds = 0;
	const ul = el("ul", [], [], ForList<number>({
		each: l,
		children: (item) => { builds = builds + 1; return <li>{"" + item()}</li>; },
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	assert builds === 3, "three rows built";
	l.move(0, 2);
	assert builds === 3, "move builds nothing";
	l.remove(0);
	assert builds === 3, "remove builds nothing";
	l.insert(0, 7);
	assert builds === 4, "insert builds exactly one row";
	d();
}

test "move only reorders the host nodes" {
	const l = createList<number>([1, 2, 3, 4]);
	const ul = el("ul", [], [], ForList<number>({ each: l, children: numberRow }));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	l.move(0, 2);
	assert rowText(ulNode) === "2314", "forward move: " + rowText(ulNode);
	l.move(3, 0);
	assert rowText(ulNode) === "4231", "backward move: " + rowText(ulNode);
	l.move(1, 2);
	assert rowText(ulNode) === "4321", "neighbour swap: " + rowText(ulNode);
	d();
}

test "remove takes the row's host nodes out and disposes its scope" {
	const l = createList<number>([1, 2, 3]);
	let cleanups = 0;
	const ul = el("ul", [], [], ForList<number>({
		each: l,
		children: (item) => {
			onCleanup(() => { cleanups = cleanups + 1; });
			return <li>{"" + item()}</li>;
		},
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	l.remove(1);
	assert rowText(ulNode) === "13", "middle row gone: " + rowText(ulNode);
	assert cleanups === 1, "its scope was disposed";
	l.remove(1);
	assert rowText(ulNode) === "1", "tail row gone: " + rowText(ulNode);
	l.remove(0);
	assert rowText(ulNode) === "", "empty: " + rowText(ulNode);
	assert cleanups === 3, "one cleanup per removed row";
	d();
}

test "set updates the row in place through its own signal" {
	const l = createList<number>([1, 2, 3]);
	let builds = 0;
	const ul = el("ul", [], [], ForList<number>({
		each: l,
		children: (item) => { builds = builds + 1; return <li>{"" + item()}</li>; },
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	l.set(1, 9);
	assert rowText(ulNode) === "193", "the row shows the new value: " + rowText(ulNode);
	assert builds === 3, "set builds no row";
	d();
}

test "a list of items with no hash mounts and takes push, set, move and remove" {
	const l = createList<GridLine>([{ text: "a", runs: [{ units: 1 }], cursorCell: -1 }]);
	const ul = el("ul", [], [], ForList<GridLine>({ each: l, children: gridRow }));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	assert rowText(ulNode) === "a1", "initial: " + rowText(ulNode);
	l.push({ text: "b", runs: [{ units: 1 }, { units: 2 }], cursorCell: 0 });
	l.push({ text: "c", runs: [], cursorCell: 2 });
	assert rowText(ulNode) === "a1b2c0", "push: " + rowText(ulNode);
	l.set(0, { text: "A", runs: [{ units: 1 }, { units: 2 }, { units: 3 }], cursorCell: 1 });
	assert rowText(ulNode) === "A3b2c0", "set: " + rowText(ulNode);
	l.move(2, 0);
	assert rowText(ulNode) === "c0A3b2", "move: " + rowText(ulNode);
	l.remove(1);
	assert rowText(ulNode) === "c0b2", "remove: " + rowText(ulNode);
	d();
}

test "replaceAll keeps the row of an item that comes back, in its new place" {
	const l = createList<number>([1, 2, 3]);
	let builds = 0;
	const ul = el("ul", [], [], ForList<number>({
		each: l,
		children: (item) => { builds = builds + 1; return <li>{"" + item()}</li>; },
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	l.replaceAll([3, 1, 2]);
	assert rowText(ulNode) === "312", "reordered: " + rowText(ulNode);
	assert builds === 3, "a pure reorder builds no row";
	l.replaceAll([2, 3, 9]);
	assert rowText(ulNode) === "239", "one new item: " + rowText(ulNode);
	assert builds === 4, "only the item never seen built a row";
	l.replaceAll([]);
	assert rowText(ulNode) === "", "empty: " + rowText(ulNode);
	d();
}

test "replaceAll disposes the rows of the items that left" {
	const l = createList<number>([1, 2, 3]);
	let cleanups = 0;
	const ul = el("ul", [], [], ForList<number>({
		each: l,
		children: (item) => {
			onCleanup(() => { cleanups = cleanups + 1; });
			return <li>{"" + item()}</li>;
		},
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	l.replaceAll([2]);
	assert cleanups === 2, "the two absent items were disposed";
	l.replaceAll([]);
	assert cleanups === 3, "and the last one with the empty list";
	d();
}

test "a keyed list reuses the row of the same key and shows the new item" {
	const l = createList<Keyed>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
	let builds = 0;
	const ul = el("ul", [], [], ForList<Keyed>({
		each: l,
		keyed: (k: Keyed): number => k.id,
		children: (item) => { builds = builds + 1; return <li>{item().label}</li>; },
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	assert rowText(ulNode) === "ab", "initial: " + rowText(ulNode);
	l.replaceAll([{ id: 2, label: "B" }, { id: 1, label: "A" }]);
	assert rowText(ulNode) === "BA", "same keys, new objects, new order: " + rowText(ulNode);
	assert builds === 2, "no row was rebuilt";
	l.replaceAll([{ id: 3, label: "c" }, { id: 1, label: "A" }]);
	assert rowText(ulNode) === "cA", "one key gone, one new: " + rowText(ulNode);
	assert builds === 3, "one row built for the new key";
	d();
}

test "a duplicate key in replaceAll raises and names the key" {
	const l = createList<Keyed>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
	const ul = el("ul", [], [], ForList<Keyed>({
		each: l,
		keyed: (k: Keyed): number => k.id,
		children: (item) => <li>{item().label}</li>,
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	let caught = "";
	try { l.replaceAll([{ id: 1, label: "a" }, { id: 1, label: "b" }]); } catch (e) { caught = e.toString(); }
	resetErrorHalt();
	d();
	assert caught !== "", "a duplicate key raises";
	assert caught.includes("1"), "the message names the key: " + caught;
}

test "ops that follow a replaceAll land on the rebuilt rows" {
	const l = createList<number>([1, 2, 3]);
	const ul = el("ul", [], [], ForList<number>({ each: l, children: numberRow }));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	l.replaceAll([5, 6]);
	l.push(7);
	l.remove(0);
	assert rowText(ulNode) === "67", "reset then push then remove: " + rowText(ulNode);
	d();
}

test "a nested ForList reacts to its own list and dies with its row" {
	const outer = createList<number>([1, 2]);
	const inner = createList<number>([7]);
	let innerCleanups = 0;
	const ul = el("ul", [], [], ForList<number>({
		each: outer,
		children: (item) => el("li", [], [], ForList<number>({
			each: inner,
			children: (v) => {
				onCleanup(() => { innerCleanups = innerCleanups + 1; });
				return <b>{"" + item() + ":" + v()}</b>;
			},
		})),
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const text = mockToString(root as unknown as MockNode);
	assert text.includes("1:7") && text.includes("2:7"), "both rows mounted their nested list: " + text;
	inner.push(8);
	const grown = mockToString(root as unknown as MockNode);
	assert grown.includes("1:8") && grown.includes("2:8"), "both nested regions took the op: " + grown;
	outer.remove(0);
	assert innerCleanups === 2, "the nested rows of the removed outer row were disposed";
	const left = mockToString(root as unknown as MockNode);
	assert !left.includes("1:7"), "the removed row's nodes are gone: " + left;
	d();
}

test "disposing the region disposes every row and detaches from the list" {
	const l = createList<number>([1, 2, 3]);
	let cleanups = 0;
	const ul = el("ul", [], [], ForList<number>({
		each: l,
		children: (item) => {
			onCleanup(() => { cleanups = cleanups + 1; });
			return <li>{"" + item()}</li>;
		},
	}));
	const host = mockHost();
	const root = host.createElement("root");
	const dispose = render(ul, host, root);
	dispose();
	assert cleanups === 3, "every row was disposed";
	l.push(4);
	assert cleanups === 3, "a detached region takes no further op";
}

test "two regions over one list both follow its ops" {
	const l = createList<number>([1]);
	const host = mockHost();
	const root = host.createElement("root");
	const a = el("ul", [], [], ForList<number>({ each: l, children: numberRow }));
	const b = el("ol", [], [], ForList<number>({ each: l, children: numberRow }));
	const disposeA = render(a, host, root);
	const disposeB = render(b, host, root);
	const aNode = (root as unknown as MockNode).children[0];
	const bNode = (root as unknown as MockNode).children[1];
	l.push(2);
	l.move(0, 1);
	assert rowText(aNode) === "21", "first region: " + rowText(aNode);
	assert rowText(bNode) === "21", "second region: " + rowText(bNode);
	disposeA();
	disposeB();
}

test "a row that reads the list length stays reactive beside the ops" {
	const l = createList<number>([1, 2]);
	let runs = 0;
	const stop = createRoot((d): Dispose => {
		createRenderEffect<number>(
			(p: number | null): number => l.length(),
			(n: number, p: number | null): Cleanup | null => { runs = runs + 1; return null; },
		);
		return d;
	});
	const ul = el("ul", [], [], ForList<number>({ each: l, children: numberRow }));
	const host = mockHost();
	const root = host.createElement("root");
	const d = render(ul, host, root);
	const ulNode = (root as unknown as MockNode).children[0];
	assert runs === 1, "the length effect ran once";
	l.push(3);
	assert runs === 2, "the length effect saw the push";
	assert rowText(ulNode) === "123", "and the region applied it: " + rowText(ulNode);
	stop();
	d();
}
