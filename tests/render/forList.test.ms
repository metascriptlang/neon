import { el, NeonNode } from "../../src/render/node";
import { MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { ForList } from "../../src/macros/ui/flow";
import { createList } from "../../src/core/list";
import { Accessor } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { onCleanup } from "../../src/core/cleanup";
import { createEffect } from "../../src/core/effect";

// PARKED: every cell takes the call form ForList<T>({…}) rather than <ForList each={l}>. A row of
// ForList carries Accessor<T>, and a generic component whose row carries a distinct alias cannot be
// instantiated through createComponent, which is what a tag lowers to:
// ~/metascript/.inbox/compiler/2026-09-20-generic-callee-type-param-through-distinct-alias.md
// (the same block that keeps <Index> off the tag surface).

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
	createRoot((d) => {
		const l = createList<number>([1, 2]);
		const ul = el("ul", [], [], ForList<number>({ each: l, children: numberRow }));
		const host = mockHost();
		const root = host.createElement("root");
		render(ul, host, root);
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
	});
}

test "a row is built once and reused across insert, move and remove" {
	createRoot((d) => {
		const l = createList<number>([1, 2, 3]);
		let builds = 0;
		const ul = el("ul", [], [], ForList<number>({
			each: l,
			children: (item) => { builds = builds + 1; return <li>{"" + item()}</li>; },
		}));
		const host = mockHost();
		const root = host.createElement("root");
		render(ul, host, root);
		assert builds === 3, "three rows built";
		l.move(0, 2);
		assert builds === 3, "move builds nothing";
		l.remove(0);
		assert builds === 3, "remove builds nothing";
		l.insert(0, 7);
		assert builds === 4, "insert builds exactly one row";
		d();
	});
}

test "move only reorders the host nodes" {
	createRoot((d) => {
		const l = createList<number>([1, 2, 3, 4]);
		const ul = el("ul", [], [], ForList<number>({ each: l, children: numberRow }));
		const host = mockHost();
		const root = host.createElement("root");
		render(ul, host, root);
		const ulNode = (root as unknown as MockNode).children[0];
		l.move(0, 2);
		assert rowText(ulNode) === "2314", "forward move: " + rowText(ulNode);
		l.move(3, 0);
		assert rowText(ulNode) === "4231", "backward move: " + rowText(ulNode);
		l.move(1, 2);
		assert rowText(ulNode) === "4321", "neighbour swap: " + rowText(ulNode);
		d();
	});
}

test "remove takes the row's host nodes out and disposes its scope" {
	createRoot((d) => {
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
		render(ul, host, root);
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
	});
}

test "set updates the row in place through its own signal" {
	createRoot((d) => {
		const l = createList<number>([1, 2, 3]);
		let builds = 0;
		const ul = el("ul", [], [], ForList<number>({
			each: l,
			children: (item) => { builds = builds + 1; return <li>{"" + item()}</li>; },
		}));
		const host = mockHost();
		const root = host.createElement("root");
		render(ul, host, root);
		const ulNode = (root as unknown as MockNode).children[0];
		l.set(1, 9);
		assert rowText(ulNode) === "193", "the row shows the new value: " + rowText(ulNode);
		assert builds === 3, "set builds no row";
		d();
	});
}

test "replaceAll reuses the rows by slot and trims or grows the tail" {
	createRoot((d) => {
		const l = createList<number>([1, 2, 3]);
		let builds = 0;
		const ul = el("ul", [], [], ForList<number>({
			each: l,
			children: (item) => { builds = builds + 1; return <li>{"" + item()}</li>; },
		}));
		const host = mockHost();
		const root = host.createElement("root");
		render(ul, host, root);
		const ulNode = (root as unknown as MockNode).children[0];
		l.replaceAll([7, 8]);
		assert rowText(ulNode) === "78", "shorter: " + rowText(ulNode);
		assert builds === 3, "the two kept slots were set, not rebuilt";
		l.replaceAll([1, 2, 3, 4]);
		assert rowText(ulNode) === "1234", "longer: " + rowText(ulNode);
		assert builds === 5, "two rows built for the two new slots";
		l.replaceAll([]);
		assert rowText(ulNode) === "", "empty: " + rowText(ulNode);
		d();
	});
}

test "ops that follow a replaceAll land on the rebuilt rows" {
	createRoot((d) => {
		const l = createList<number>([1, 2, 3]);
		const ul = el("ul", [], [], ForList<number>({ each: l, children: numberRow }));
		const host = mockHost();
		const root = host.createElement("root");
		render(ul, host, root);
		const ulNode = (root as unknown as MockNode).children[0];
		l.replaceAll([5, 6]);
		l.push(7);
		l.remove(0);
		assert rowText(ulNode) === "67", "reset then push then remove: " + rowText(ulNode);
		d();
	});
}

test "a nested ForList reacts to its own list and dies with its row" {
	createRoot((d) => {
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
		render(ul, host, root);
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
	});
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
	createRoot((d) => {
		const l = createList<number>([1]);
		const host = mockHost();
		const root = host.createElement("root");
		const a = el("ul", [], [], ForList<number>({ each: l, children: numberRow }));
		const b = el("ol", [], [], ForList<number>({ each: l, children: numberRow }));
		render(a, host, root);
		render(b, host, root);
		const aNode = (root as unknown as MockNode).children[0];
		const bNode = (root as unknown as MockNode).children[1];
		l.push(2);
		l.move(0, 1);
		assert rowText(aNode) === "21", "first region: " + rowText(aNode);
		assert rowText(bNode) === "21", "second region: " + rowText(bNode);
		d();
	});
}

test "a row that reads the list length stays reactive beside the ops" {
	createRoot((d) => {
		const l = createList<number>([1, 2]);
		let runs = 0;
		createEffect(() => { l.length(); runs = runs + 1; });
		const ul = el("ul", [], [], ForList<number>({ each: l, children: numberRow }));
		const host = mockHost();
		const root = host.createElement("root");
		render(ul, host, root);
		const ulNode = (root as unknown as MockNode).children[0];
		assert runs === 1, "the length effect ran once";
		l.push(3);
		assert runs === 2, "the length effect saw the push";
		assert rowText(ulNode) === "123", "and the region applied it: " + rowText(ulNode);
		d();
	});
}
