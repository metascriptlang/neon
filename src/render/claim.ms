import { Host, HostNode } from "./hostTypes";
import { place, needsStartMarker } from "./reconcile";
import { Computation } from "../core/types";
import { getOwner, carriesId, getNextChildId } from "../core/runtime";

interface Open {
	node: HostNode;
	tag: string;
	last: HostNode | null;
	count: number;
}

interface Claim {
	host: Host;
	take: (parent: HostNode, after: HostNode | null, tag: string) => HostNode | null;
	open: Open[];
	paused: number;
	createElement: (tag: string) => HostNode;
	createText: (s: string) => HostNode;
	append: (parent: HostNode, child: HostNode) => void;
	insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null) => void;
	cloneNode: ((node: HostNode) => HostNode) | null;
}

let active: Claim | null = null;

function reading(host: Host): Claim | null {
	const c = active;
	if (c === null || c.host !== host || c.paused > 0) { return null; }
	return c;
}

function pathOf(c: Claim): string {
	let s = "the container";
	for (let i = 1; i < c.open.length; i += 1) { s = (i === 1 ? "" : s + " > ") + c.open[i].tag; }
	return s;
}

function claimNext(c: Claim, tag: string): HostNode {
	const top = c.open[c.open.length - 1];
	const node = c.take(top.node, top.last, tag);
	if (node === null) {
		throw "hydrate: the page has no " + (tag === "" ? "text" : "<" + tag + ">") + " at child " + (top.count + 1).toString() + " of " + pathOf(c);
	}
	top.last = node;
	top.count += 1;
	if (tag !== "") { c.open.push({ node: node as HostNode, tag, last: null, count: 0 }); }
	return node as HostNode;
}

function leftover(c: Claim, o: Open): boolean {
	return o.count > 0 && c.host.nextSibling(o.last as HostNode) !== null;
}

function settle(c: Claim, parent: HostNode, node: HostNode): void {
	let top = c.open[c.open.length - 1];
	if (top.node === node && c.open.length > 1) {
		if (leftover(c, top)) { throw "hydrate: the page has more children in " + pathOf(c) + " than the tree renders"; }
		c.open.pop();
		top = c.open[c.open.length - 1];
	}
	if (top.node !== parent) { throw "hydrate: a node read from " + pathOf(c) + " was placed into another parent"; }
}

export function beginClaim(host: Host, container: HostNode): void {
	if (active !== null) { throw "hydrate: another hydrate is still running"; }
	const take = host.claim;
	if (take === null) { throw "hydrate: this host has no claim capability, so it cannot take over a page's nodes"; }
	const c: Claim = {
		host,
		take: take as (parent: HostNode, after: HostNode | null, tag: string) => HostNode | null,
		open: [{ node: container, tag: "", last: null, count: 0 }],
		paused: 0,
		createElement: host.createElement,
		createText: host.createText,
		append: host.append,
		insertBefore: host.insertBefore,
		cloneNode: host.cloneNode,
	};
	host.createElement = (tag: string): HostNode => c.paused > 0 ? c.createElement(tag) : claimNext(c, tag);
	host.createText = (s: string): HostNode => c.paused > 0 ? c.createText(s) : claimNext(c, "");
	host.append = (parent: HostNode, child: HostNode): void => {
		if (c.paused > 0) { c.append(parent, child); } else { settle(c, parent, child); }
	};
	host.insertBefore = (parent: HostNode, node: HostNode, ref: HostNode | null): void => {
		if (c.paused > 0) { c.insertBefore(parent, node, ref); } else { settle(c, parent, node); }
	};
	host.cloneNode = null;
	active = c;
}

export function endClaim(host: Host, complete: boolean): void {
	const c = active;
	if (c === null || c.host !== host) { return; }
	host.createElement = c.createElement;
	host.createText = c.createText;
	host.append = c.append;
	host.insertBefore = c.insertBefore;
	host.cloneNode = c.cloneNode;
	active = null;
	if (!complete) { return; }
	if (c.open.length > 1) { throw "hydrate: " + pathOf(c) + " was read from the page but never placed"; }
	const root = c.open[0];
	const rest = root.last === null ? host.firstChild(root.node) : host.nextSibling(root.last as HostNode);
	if (rest !== null) { throw "hydrate: the page has more children in the container than the tree renders"; }
}

export function unclaimed(host: Host, mount: () => void): void {
	const c = reading(host);
	if (c === null) { mount(); return; }
	c.paused += 1;
	try {
		mount();
	} finally {
		c.paused -= 1;
	}
}

export function regionAnchor(host: Host, parent: HostNode, before: HostNode | null): HostNode {
	if (needsStartMarker(parent)) { place(host, parent, host.createText(""), before); }
	const c = reading(host);
	if (c !== null) { return c.createText(""); }
	const anchor = host.createText("");
	place(host, parent, anchor, before);
	return anchor;
}

export function regionParent(host: Host, anchor: HostNode, region: string): HostNode {
	const p = host.parentOf(anchor);
	if (p === null) { throw region + ": the region's anchor has no parent at an update, so there is nowhere to put its rows"; }
	return p as HostNode;
}

export function sealRegion(host: Host, parent: HostNode, anchor: HostNode): void {
	const c = reading(host);
	if (c === null) { return; }
	const served = claimNext(c, "");
	c.paused += 1;
	try {
		place(host, parent, anchor, served);
	} finally {
		c.paused -= 1;
	}
	host.removeChild(parent, served);
	c.open[c.open.length - 1].last = anchor;
}

// A ForList on the server writes its rows without the effect the client follows its
// list with; that effect's id slot is taken all the same, so every id after the list
// matches the client's.
export function skipRegionEffect(): void {
	const o = getOwner();
	if (carriesId(o)) { getNextChildId(o as Computation); }
}

export function serverRegionStart(host: Host, parent: HostNode, before: HostNode | null): void {
	if (needsStartMarker(parent)) { place(host, parent, host.createText(""), before); }
}

export function serverRegionEnd(host: Host, parent: HostNode, before: HostNode | null): void {
	place(host, parent, host.createText(""), before);
}
