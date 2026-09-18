import { Host, HostNode } from "../../src/render/hostTypes";
import { reconcileArrays, Row, rowOf } from "../../src/render/reconcile";

export const HOST_MOVE_CONTRACT = "abc abc cab abc bac insert-throws remove-throws bac";
export const RECONCILE_CONTRACT = "abc_ cba_ acd_ deac_ b_ _";
export const HOST_ATTR_CONTRACT = "_ title=a,id=x id=x id=x,title=b id=x,title=b";

function nameOf(nodes: HostNode[], names: string[], n: HostNode): string {
	for (let i = 0; i < nodes.length; i += 1) {
		if (nodes[i] === n) { return names[i]; }
	}
	return "?";
}

export function childOrder(h: Host, parent: HostNode, nodes: HostNode[], names: string[]): string {
	let out = "";
	let c = h.firstChild(parent);
	while (c !== null) {
		const n = c as HostNode;
		out = out + nameOf(nodes, names, n);
		c = h.nextSibling(n);
	}
	return out;
}

export function hostMoveContract(h: Host): string {
	const root = h.createElement("view");
	const a = h.createElement("view");
	const b = h.createElement("view");
	const c = h.createElement("view");
	const nodes: HostNode[] = [a, b, c];
	const names: string[] = ["a", "b", "c"];
	h.append(root, a);
	h.append(root, b);
	h.append(root, c);
	let log = childOrder(h, root, nodes, names);
	h.insertBefore(root, b, b);
	log = log + " " + childOrder(h, root, nodes, names);
	h.insertBefore(root, c, a);
	log = log + " " + childOrder(h, root, nodes, names);
	h.insertBefore(root, c, null);
	log = log + " " + childOrder(h, root, nodes, names);
	h.insertBefore(root, a, c);
	log = log + " " + childOrder(h, root, nodes, names);
	const stranger = h.createElement("view");
	let insertThrew = false;
	try {
		h.insertBefore(root, h.createElement("view"), stranger);
	} catch (e) {
		insertThrew = true;
	}
	log = log + (insertThrew ? " insert-throws" : " insert-silent");
	let removeThrew = false;
	try {
		h.removeChild(root, stranger);
	} catch (e) {
		removeThrew = true;
	}
	log = log + (removeThrew ? " remove-throws" : " remove-silent");
	log = log + " " + childOrder(h, root, nodes, names);
	return log;
}

export function reconcileContract(h: Host): string {
	const root = h.createElement("view");
	const anchor = h.createText("");
	h.append(root, anchor);
	const a = h.createElement("view");
	const b = h.createElement("view");
	const c = h.createElement("view");
	const d = h.createElement("view");
	const e = h.createElement("view");
	const nodes: HostNode[] = [a, b, c, d, e, anchor];
	const names: string[] = ["a", "b", "c", "d", "e", "_"];
	const ra = rowOf(a);
	const rb = rowOf(b);
	const rc = rowOf(c);
	const rd = rowOf(d);
	const re = rowOf(e);
	const s1: Row[] = [ra, rb, rc];
	reconcileArrays(h, root, [], s1, anchor);
	let log = childOrder(h, root, nodes, names);
	const s2: Row[] = [rc, rb, ra];
	reconcileArrays(h, root, s1, s2, anchor);
	log = log + " " + childOrder(h, root, nodes, names);
	const s3: Row[] = [ra, rc, rd];
	reconcileArrays(h, root, s2, s3, anchor);
	log = log + " " + childOrder(h, root, nodes, names);
	const s4: Row[] = [rd, re, ra, rc];
	reconcileArrays(h, root, s3, s4, anchor);
	log = log + " " + childOrder(h, root, nodes, names);
	const s5: Row[] = [rb];
	reconcileArrays(h, root, s4, s5, anchor);
	log = log + " " + childOrder(h, root, nodes, names);
	reconcileArrays(h, root, s5, [], anchor);
	log = log + " " + childOrder(h, root, nodes, names);
	return log;
}

export function hostAttrContract(h: Host, read: (n: HostNode) => string): string {
	const n = h.createElement("view");
	h.removeAttr(n, "title");
	let log = read(n);
	h.setAttr(n, "title", "a");
	h.setAttr(n, "id", "x");
	log = log + " " + read(n);
	h.removeAttr(n, "title");
	log = log + " " + read(n);
	h.setAttr(n, "title", "b");
	log = log + " " + read(n);
	h.removeAttr(n, "missing");
	log = log + " " + read(n);
	return log;
}
