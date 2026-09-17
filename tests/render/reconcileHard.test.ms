import { mockHost, MockNode, HostNode } from "../../src/render/host";
import { reconcileArrays, Range, rangeOf } from "../../src/render/reconcile";

function seq(parent: HostNode): string {
	const p = parent as unknown as MockNode;
	let s = "";
	for (const c of p.children) { s = s + c.tag; }
	return s;
}

test "reconcileArrays forces the map-fallback branch (non-swap middle reorder)" {
	const h = mockHost();
	const parent = h.createElement("ul");
	const pool = new Map<string, Range>();
	for (const L of ["A", "B", "C", "D", "E"]) { pool.set(L, rangeOf(h.createElement(L))); }
	function nodesFor(s: string): Range[] {
		const out: Range[] = [];
		for (let i = 0; i < s.length; i += 1) { out.push(pool.get(s.slice(i, i + 1)) as Range); }
		return out;
	}
	let cur = nodesFor("ABCD");
	for (const n of cur) { h.append(parent, n.start); }
	function go(next: string): void {
		const b = nodesFor(next);
		reconcileArrays(h, parent, cur, b, null as unknown as HostNode);
		cur = b;
	}
	go("BADC");
	assert seq(parent) === "BADC", "interleaved reorder";
	go("CDEAB");
	assert seq(parent) === "CDEAB", "rotate by 2";
	go("ADBEC");
	assert seq(parent) === "ADBEC", "scattered shuffle";
	go("EDCBA");
	assert seq(parent) === "EDCBA", "full reverse from shuffle";
}

test "reconcileArrays handles duplicate keys" {
	const h = mockHost();
	const parent = h.createElement("ul");
	const a = rangeOf(h.createElement("A"));
	const b1 = rangeOf(h.createElement("B"));
	const b2 = rangeOf(h.createElement("B"));
	const c = rangeOf(h.createElement("C"));
	// note: b1 and b2 are distinct nodes that share tag "B"
	let cur: Range[] = [a, b1, b2, c];
	for (const n of cur) { h.append(parent, n.start); }
	assert seq(parent) === "ABBC", "initial";

	const next: Range[] = [c, b2, a, b1];
	reconcileArrays(h, parent, cur, next, null as unknown as HostNode);
	// distinct node identities must land in exactly the requested order
	const p = parent as unknown as MockNode;
	assert p.children[0] === (c.start as unknown as MockNode), "pos0 = C";
	assert p.children[1] === (b2.start as unknown as MockNode), "pos1 = b2";
	assert p.children[2] === (a.start as unknown as MockNode), "pos2 = A";
	assert p.children[3] === (b1.start as unknown as MockNode), "pos3 = b1";
}
