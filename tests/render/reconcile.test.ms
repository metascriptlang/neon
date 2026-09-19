import { mockHost, MockNode, HostNode, Host, NeonNode } from "../../src/render/host";
import { reconcileArrays, Row, rowOf, makeRow, place, moveRow, removeRow } from "../../src/render/reconcile";

function seq(parent: HostNode): string {
	const p = parent as unknown as MockNode;
	let s = "";
	for (const c of p.children) { s = s + c.tag; }
	return s;
}

test "reconcileArrays drives many transforms with node reuse" {
	const h = mockHost();
	const parent = h.createElement("ul");
	const pool = new Map<string, Row>();
	const labels = ["A", "B", "C", "D", "E", "F"];
	for (const L of labels) { pool.set(L, rowOf(h.createElement(L))); }

	function nodesFor(s: string): Row[] {
		const out: Row[] = [];
		for (let i = 0; i < s.length; i += 1) { out.push(pool.get(s.slice(i, i + 1)) as Row); }
		return out;
	}

	let cur = nodesFor("ABC");
	for (const n of cur) { h.append(parent, n.start); }
	assert seq(parent) === "ABC", "initial ABC";

	function go(next: string): void {
		const b = nodesFor(next);
		reconcileArrays(h, parent, cur, b, null as unknown as HostNode);
		cur = b;
	}

	go("ACB");
	assert seq(parent) === "ACB", "swap tail";
	go("CAB");
	assert seq(parent) === "CAB", "rotate left";
	go("ABCDEF");
	assert seq(parent) === "ABCDEF", "reorder + append";
	go("FEDCBA");
	assert seq(parent) === "FEDCBA", "full reverse";
	go("FA");
	assert seq(parent) === "FA", "remove many";
	go("");
	assert seq(parent) === "", "remove all";
	go("ABC");
	assert seq(parent) === "ABC", "rebuild from empty";
	go("BCA");
	assert seq(parent) === "BCA", "rotate right";
}

test "reconcileArrays keeps region before a trailing anchor" {
	const h = mockHost();
	const parent = h.createElement("ul");
	const pool = new Map<string, Row>();
	for (const L of ["A", "B", "C"]) { pool.set(L, rowOf(h.createElement(L))); }
	const a = pool.get("A") as Row;
	const b = pool.get("B") as Row;
	const c = pool.get("C") as Row;

	h.append(parent, a.start);
	h.append(parent, b.start);
	const anchor = h.createText("|");
	h.append(parent, anchor);

	let cur: Row[] = [a, b];
	const next: Row[] = [a, b, c];
	reconcileArrays(h, parent, cur, next, anchor);

	const p = parent as unknown as MockNode;
	assert seq(parent) === "ABC", "C inserted into region";
	assert p.children[p.children.length - 1] === (anchor as unknown as MockNode), "anchor stays last";
}

function span(h: Host, parent: HostNode, tags: string[]): Row {
	const made: HostNode[] = [];
	for (const t of tags) {
		const n = h.createElement(t);
		h.append(parent, n);
		made.push(n);
	}
	const r = rowOf(made[0]);
	r.end = made[made.length - 1];
	return r;
}

test "a range of several nodes moves and is removed as one block" {
	const h = mockHost();
	const parent = h.createElement("ul");
	const first = span(h, parent, ["A", "a"]);
	const second = span(h, parent, ["B", "b", "b"]);
	const third = span(h, parent, ["C"]);
	assert seq(parent) === "AaBbbC", "initial";

	let cur: Row[] = [first, second, third];
	let next: Row[] = [third, first, second];
	reconcileArrays(h, parent, cur, next, null as unknown as HostNode);
	assert seq(parent) === "CAaBbb", "whole blocks rotate, never interleave";

	cur = next;
	next = [second, third];
	reconcileArrays(h, parent, cur, next, null as unknown as HostNode);
	assert seq(parent) === "BbbC", "a removed range takes all of its nodes";

	cur = next;
	next = [third, second];
	reconcileArrays(h, parent, cur, next, null as unknown as HostNode);
	assert seq(parent) === "CBbb", "swap of two ranges";
}

test "ranges keep their place around a trailing anchor" {
	const h = mockHost();
	const parent = h.createElement("ul");
	const one = span(h, parent, ["A", "a"]);
	const two = span(h, parent, ["B", "b"]);
	const anchor = h.createText("|");
	h.append(parent, anchor);
	const three = span(h, parent, ["C", "c"]);

	reconcileArrays(h, parent, [one, two], [two, three, one], anchor);
	const p = parent as unknown as MockNode;
	assert seq(parent) === "BbCcAa", "a block from outside the region moves into it whole: " + seq(parent);
	assert p.children[p.children.length - 1] === (anchor as unknown as MockNode), "anchor stays last";
}

test "moveRow and removeRow carry every node of a block" {
	const h = mockHost();
	const parent = h.createElement("ul");
	const one = span(h, parent, ["A", "a", "a"]);
	const two = span(h, parent, ["B", "b"]);
	const tail = h.createElement("Z");
	h.append(parent, tail);
	assert seq(parent) === "AaaBbZ", "initial";

	moveRow(h, parent, one, tail);
	assert seq(parent) === "BbAaaZ", "a block moves in one piece: " + seq(parent);

	moveRow(h, parent, two, null as unknown as HostNode);
	assert seq(parent) === "AaaZBb", "a block moves to the end: " + seq(parent);

	moveRow(h, parent, two, two.start);
	assert seq(parent) === "AaaZBb", "moving a block before itself changes nothing";

	removeRow(h, parent, one);
	assert seq(parent) === "ZBb", "a removed block takes every node: " + seq(parent);
}

let fuzzSeed: number = 12345.0;
function fuzzRnd(n: number): number {
	fuzzSeed = (fuzzSeed * 1103515.0 + 12345.0) % 2147483.0;
	return Math.floor(fuzzSeed % n);
}

function fragmentOf(tags: string[]): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		for (const t of tags) { place(host, parent, host.createElement(t), before); }
	};
}

test "fragment rows of one to three nodes survive random reorder, drop and remount" {
	let fails = 0;
	let firstMismatch = "";
	let multi = 0;
	for (let trial = 0; trial < 400; trial += 1) {
		const h = mockHost();
		const parent = h.createElement("ul");
		h.append(parent, h.createElement("head"));
		const anchor = h.createElement("tail");
		h.append(parent, anchor);
		const count = 2 + fuzzRnd(6);
		const views: NeonNode[] = [];
		const texts: string[] = [];
		const rows: (Row | null)[] = [];
		for (let i = 0; i < count; i += 1) {
			const size = 1 + fuzzRnd(3);
			if (size > 1) { multi = multi + 1; }
			const tags: string[] = [];
			let t = "";
			for (let k = 0; k < size; k += 1) {
				const tag = i.toString() + "." + k.toString();
				tags.push(tag);
				t = t + tag;
			}
			views.push(fragmentOf(tags));
			texts.push(t);
			rows.push(null);
		}
		let cur: Row[] = [];
		for (let step = 0; step < 6; step += 1) {
			const next: Row[] = [];
			const picked: boolean[] = [];
			const pool: number[] = [];
			for (let i = 0; i < count; i += 1) { picked.push(false); pool.push(i); }
			let want = "head";
			const keep = fuzzRnd(count + 1);
			for (let i = 0; i < keep; i += 1) {
				const pick = fuzzRnd(pool.length);
				const idx = pool[pick];
				pool.splice(pick, 1);
				picked[idx] = true;
				if (rows[idx] === null) { rows[idx] = makeRow(views[idx]); }
				next.push(rows[idx] as Row);
				want = want + texts[idx];
			}
			want = want + "tail";
			reconcileArrays(h, parent, cur, next, anchor);
			for (let i = 0; i < count; i += 1) {
				if (!picked[i]) { rows[i] = null; }
			}
			if (seq(parent) !== want) {
				fails = fails + 1;
				if (firstMismatch === "") { firstMismatch = "want=" + want + " got=" + seq(parent); }
			}
			cur = next;
		}
	}
	assert multi > 1000, "the fuzz exercised multi-node rows: " + multi.toString();
	assert fails === 0, fails.toString() + " of 2400 steps lost or misplaced a node, first: " + firstMismatch;
}
