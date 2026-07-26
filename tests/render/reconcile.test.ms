import { mockHost, MockNode, HostNode } from "../../src/render/host";
import { reconcileArrays } from "../../src/render/reconcile";

function seq(parent: HostNode): string {
	const p = parent as unknown as MockNode;
	let s = "";
	for (const c of p.children) { s = s + c.tag; }
	return s;
}

test "reconcileArrays drives many transforms with node reuse" {
	const h = mockHost();
	const parent = h.createElement("ul");
	const pool = new Map<string, HostNode>();
	const labels = ["A", "B", "C", "D", "E", "F"];
	for (const L of labels) { pool.set(L, h.createElement(L)); }

	function nodesFor(s: string): HostNode[] {
		const out: HostNode[] = [];
		for (let i = 0; i < s.length; i += 1) { out.push(pool.get(s.slice(i, i + 1)) as HostNode); }
		return out;
	}

	let cur = nodesFor("ABC");
	for (const n of cur) { h.append(parent, n); }
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
	const pool = new Map<string, HostNode>();
	for (const L of ["A", "B", "C"]) { pool.set(L, h.createElement(L)); }
	const a = pool.get("A") as HostNode;
	const b = pool.get("B") as HostNode;
	const c = pool.get("C") as HostNode;

	h.append(parent, a);
	h.append(parent, b);
	const anchor = h.createText("|");
	h.append(parent, anchor);

	let cur: HostNode[] = [a, b];
	const next: HostNode[] = [a, b, c];
	reconcileArrays(h, parent, cur, next, anchor);

	const p = parent as unknown as MockNode;
	assert seq(parent) === "ABC", "C inserted into region";
	assert p.children[p.children.length - 1] === (anchor as unknown as MockNode), "anchor stays last";
}
