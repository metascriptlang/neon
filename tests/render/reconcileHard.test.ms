import { mockHost, MockNode, HostNode } from "../../src/render/host";
import { reconcileArrays } from "../../src/render/reconcile";

function seq(parent: HostNode): string {
	const p = parent as unknown as MockNode;
	let s = "";
	for (const c of p.children) { s = s + c.tag; }
	return s;
}

test "reconcileArrays forces the map-fallback branch (non-swap middle reorder)" {
	const h = mockHost();
	const parent = h.createElement("ul");
	const pool = new Map<string, HostNode>();
	for (const L of ["A", "B", "C", "D", "E"]) { pool.set(L, h.createElement(L)); }
	function nodesFor(s: string): HostNode[] {
		const out: HostNode[] = [];
		for (let i = 0; i < s.length; i += 1) { out.push(pool.get(s.slice(i, i + 1)) as HostNode); }
		return out;
	}
	let cur = nodesFor("ABCD");
	for (const n of cur) { h.append(parent, n); }
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
	const a = h.createElement("A");
	const b1 = h.createElement("B");
	const b2 = h.createElement("B");
	const c = h.createElement("C");
	// note: b1 and b2 are distinct nodes that share tag "B"
	let cur: HostNode[] = [a, b1, b2, c];
	for (const n of cur) { h.append(parent, n); }
	assert seq(parent) === "ABBC", "initial";

	const next: HostNode[] = [c, b2, a, b1];
	reconcileArrays(h, parent, cur, next, null as unknown as HostNode);
	// distinct node identities must land in exactly the requested order
	const p = parent as unknown as MockNode;
	assert p.children[0] === (c as unknown as MockNode), "pos0 = C";
	assert p.children[1] === (b2 as unknown as MockNode), "pos1 = b2";
	assert p.children[2] === (a as unknown as MockNode), "pos2 = A";
	assert p.children[3] === (b1 as unknown as MockNode), "pos3 = b1";
}
