import { mockHost, MockNode, HostNode, Host } from "../../src/render/host";
import { reconcileArrays, Row, rowOf, makeRow, place } from "../../src/render/reconcile";
import { createRoot } from "../../src/core/owner";

const N = 200;

interface Counted {
	host: Host;
	parent: HostNode;
	rows: Row[];
}

let inserts = 0;
let removes = 0;

function countingHost(): Host {
	const h = mockHost();
	return {
		createElement: h.createElement,
		createText: h.createText,
		setText: h.setText,
		setAttr: h.setAttr,
		removeAttr: h.removeAttr,
		setStyle: h.setStyle,
		setStyleProp: h.setStyleProp,
		setStyleClass: h.setStyleClass,
		addEvent: h.addEvent,
		append: h.append,
		insertBefore: (p: HostNode, n: HostNode, ref: HostNode | null): void => { inserts = inserts + 1; h.insertBefore(p, n, ref); },
		removeChild: (p: HostNode, n: HostNode): void => { removes = removes + 1; h.removeChild(p, n); },
		nextSibling: h.nextSibling,
		firstChild: h.firstChild,
		cloneNode: null,
	};
}

function mounted(): Counted {
	const host = countingHost();
	const parent = host.createElement("ul");
	const rows: Row[] = [];
	for (let i = 0; i < N; i += 1) {
		const node = host.createElement("li");
		host.append(parent, node);
		rows.push(rowOf(node));
	}
	inserts = 0;
	removes = 0;
	return { host, parent, rows };
}

function order(parent: HostNode): MockNode[] {
	return (parent as unknown as MockNode).children;
}

function copyOf(rows: Row[]): Row[] {
	const out: Row[] = [];
	for (const r of rows) { out.push(r); }
	return out;
}

test "swapping two rows moves two rows" {
	const c = mounted();
	const next = copyOf(c.rows);
	const t = next[1];
	next[1] = next[N - 2];
	next[N - 2] = t;
	reconcileArrays(c.host, c.parent, c.rows, next, null);
	assert inserts === 2, "a swap of two rows takes two insertBefore, got " + inserts.toString();
	assert removes === 0, "a swap removes nothing, got " + removes.toString();
	assert order(c.parent)[1] === next[1].start as unknown as MockNode, "row 1 holds the swapped row";
	assert order(c.parent)[N - 2] === next[N - 2].start as unknown as MockNode, "row N-2 holds the swapped row";
}

test "reversing a list moves at most one row per position" {
	const c = mounted();
	const next: Row[] = [];
	for (let i = N - 1; i >= 0; i -= 1) { next.push(c.rows[i]); }
	reconcileArrays(c.host, c.parent, c.rows, next, null);
	assert inserts <= N, "a reverse takes at most N insertBefore, got " + inserts.toString();
	assert removes === 0, "a reverse removes nothing, got " + removes.toString();
	const seen = order(c.parent);
	assert seen[0] === next[0].start as unknown as MockNode, "the reversed head is first";
	assert seen[N - 1] === next[N - 1].start as unknown as MockNode, "the reversed tail is last";
}

test "moving one row to the front moves one row" {
	const c = mounted();
	const next = copyOf(c.rows);
	const moved = next[N - 1];
	next.splice(N - 1, 1);
	next.splice(0, 0, moved);
	reconcileArrays(c.host, c.parent, c.rows, next, null);
	assert inserts === 1, "one row to the front takes one insertBefore, got " + inserts.toString();
	assert order(c.parent)[0] === moved.start as unknown as MockNode, "the moved row is first";
}

test "removing half a list moves nothing" {
	const c = mounted();
	const next: Row[] = [];
	for (let i = 0; i < N / 2; i += 1) { next.push(c.rows[i]); }
	reconcileArrays(c.host, c.parent, c.rows, next, null);
	assert removes === N / 2, "half the rows are removed, got " + removes.toString();
	assert inserts === 0, "removing a tail moves nothing, got " + inserts.toString();
}

function tags(parent: HostNode): string {
	let out = "";
	for (const c of (parent as unknown as MockNode).children) { out = out + c.tag; }
	return out;
}

test "a row body runs in list order, whichever rows move around it" {
	createRoot((dispose) => {
		const host = mockHost();
		const parent = host.createElement("ul");
		const ran: string[] = [];
		function rowFor(tag: string): Row {
			return makeRow((h: Host, p: HostNode, before: HostNode | null): void => {
				ran.push(tag);
				place(h, p, h.createElement(tag), before);
			});
		}

		const a = rowFor("A");
		const b = rowFor("B");
		const c = rowFor("C");
		const first: Row[] = [a, b, c];
		reconcileArrays(host, parent, [], first, null);
		assert ran.join("") === "ABC", "first mount runs in list order, got " + ran.join("");
		assert tags(parent) === "ABC", "first mount lands in list order, got " + tags(parent);

		const d = rowFor("D");
		const e = rowFor("E");
		const next: Row[] = [c, d, a, e, b];
		reconcileArrays(host, parent, first, next, null);
		assert ran.join("") === "ABCDE", "the new rows run in list order after the old ones, got " + ran.join("");
		assert tags(parent) === "CDAEB", "new rows land between rows that moved, got " + tags(parent);
		return 0;
	});
}

test "a row mounted into a region lands before the trailing anchor" {
	createRoot((dispose) => {
		const host = mockHost();
		const parent = host.createElement("ul");
		const anchor = host.createElement("anchor");
		host.append(parent, anchor);
		const rows: Row[] = [];
		for (const tag of ["A", "B"]) {
			rows.push(makeRow((h: Host, p: HostNode, before: HostNode | null): void => {
				place(h, p, h.createElement(tag), before);
			}));
		}
		reconcileArrays(host, parent, [], rows, anchor);
		assert tags(parent) === "ABanchor", "rows mount in front of the anchor, got " + tags(parent);

		const flipped: Row[] = [rows[1], rows[0]];
		reconcileArrays(host, parent, rows, flipped, anchor);
		assert tags(parent) === "BAanchor", "a reorder keeps the anchor last, got " + tags(parent);
		return 0;
	});
}
