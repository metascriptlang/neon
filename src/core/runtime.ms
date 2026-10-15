import {
	Computation, Source, Link, ErrorHandler,
	REACTIVE_CHECK, REACTIVE_DIRTY, REACTIVE_RECOMPUTING_DEPS, REACTIVE_IN_HEAP, REACTIVE_IN_HEAP_HEIGHT,
	REACTIVE_DISPOSED, REACTIVE_LAZY, REACTIVE_MISSED_WAKE,
	CONFIG_TRANSPARENT, CONFIG_AUTO_DISPOSE, CONFIG_STAGED, CONFIG_PROMOTED, CONFIG_ROOT, CONFIG_MODIFIED,
	CONFIG_DORMANT_QUEUED, EFFECT_PURE, EFFECT_RENDER, RUN_UNCHANGED, RUN_STAGED,
} from "./types";

const LOOP_LIMIT: int32 = 100000;

let currentOwner: Computation | null = null;
let tracking: boolean = false;
let scheduled: boolean = false;
let running: boolean = false;
let syncDepth: int32 = 0;
let deferDepth: int32 = 0;
let unflushedStaged: boolean = false;
let dormantPending: boolean = false;
let serverDepth: int32 = 0;

let heapHead: (Computation | null)[] = [null];
let heapTail: (Computation | null)[] = [null];
let heapMin: int32 = 0;
let heapMax: int32 = 0;
let heapMarked: boolean = false;

let pendingNodes: Source[] = [];
let promotedWrites: Source[] = [];
let dormantNodes: Computation[] = [];
let renderQueue: Computation[] = [];
let userQueue: Computation[] = [];

export function getOwner(): Computation | null { return currentOwner; }
export function setOwner(o: Computation | null): void { currentOwner = o; }
export function isTracking(): boolean { return tracking; }
export function setTracking(t: boolean): void { tracking = t; }
export function onServer(): boolean { return serverDepth > 0; }
export function getServerDepth(): number { return serverDepth; }
export function setServerDepth(d: number): void { serverDepth = d as int32; }
export function isStaged(el: Source): boolean { return (el.config & CONFIG_STAGED) !== 0; }
export function isDisposed(node: Computation): boolean { return (node.flags & REACTIVE_DISPOSED) !== 0; }

export function newSource(config: int32): Source {
	return { subs: null, subsTail: null, config, computed: false, commit: null };
}

function growHeap(height: int32): void {
	while (heapHead.length <= height) {
		heapHead.push(null);
		heapTail.push(null);
	}
}

function actualInsertIntoHeap(n: Computation): void {
	const parent = n.parent;
	let parentHeight: int32 = -1;
	if (parent !== null) {
		const via = (parent.config & CONFIG_ROOT) !== 0 ? parent.parentComputed : parent;
		if (via !== null) { parentHeight = via.height; }
	}
	if (parentHeight >= n.height) { n.height = parentHeight + 1; }
	const height = n.height;
	growHeap(height);
	const tail = heapTail[height];
	n.nextHeap = null;
	n.prevHeap = tail;
	if (tail === null) { heapHead[height] = n; } else { tail.nextHeap = n; }
	heapTail[height] = n;
	if (height > heapMax) { heapMax = height; }
}

function insertIntoHeap(n: Computation): void {
	const flags = n.flags;
	if ((flags & (REACTIVE_IN_HEAP | REACTIVE_RECOMPUTING_DEPS)) !== 0) { return; }
	if ((flags & REACTIVE_CHECK) !== 0) {
		n.flags = (flags & ~(REACTIVE_CHECK | REACTIVE_DIRTY)) | REACTIVE_DIRTY | REACTIVE_IN_HEAP;
	} else {
		n.flags = flags | REACTIVE_IN_HEAP;
		if (heapMarked) { markNode(n, REACTIVE_DIRTY); }
	}
	if ((flags & REACTIVE_IN_HEAP_HEIGHT) === 0) { actualInsertIntoHeap(n); }
}

function insertIntoHeapHeight(n: Computation): void {
	const flags = n.flags;
	if ((flags & (REACTIVE_IN_HEAP | REACTIVE_RECOMPUTING_DEPS | REACTIVE_IN_HEAP_HEIGHT)) !== 0) { return; }
	n.flags = flags | REACTIVE_IN_HEAP_HEIGHT;
	actualInsertIntoHeap(n);
}

function deleteFromHeap(n: Computation): void {
	const flags = n.flags;
	if ((flags & (REACTIVE_IN_HEAP | REACTIVE_IN_HEAP_HEIGHT)) === 0) { return; }
	n.flags = flags & ~(REACTIVE_IN_HEAP | REACTIVE_IN_HEAP_HEIGHT);
	const height = n.height;
	const prev = n.prevHeap;
	const next = n.nextHeap;
	if (prev !== null) { prev.nextHeap = next; } else { heapHead[height] = next; }
	if (next !== null) { next.prevHeap = prev; } else { heapTail[height] = prev; }
	n.prevHeap = null;
	n.nextHeap = null;
}

function markNode(el: Computation, newState: int32): void {
	const flags = el.flags;
	if ((flags & (REACTIVE_CHECK | REACTIVE_DIRTY)) >= newState) { return; }
	el.flags = (flags & ~(REACTIVE_CHECK | REACTIVE_DIRTY)) | newState;
	for (let l = el.subs; l !== null; l = l.nextSub) {
		markNode(l.sub, REACTIVE_CHECK);
	}
}

function markHeap(): void {
	if (heapMarked) { return; }
	heapMarked = true;
	for (let i = 0; i <= heapMax; i += 1) {
		for (let el = heapHead[i]; el !== null; el = el.nextHeap) {
			if ((el.flags & REACTIVE_IN_HEAP) !== 0) { markNode(el, REACTIVE_DIRTY); }
		}
	}
}

function adjustHeight(el: Computation): void {
	deleteFromHeap(el);
	let newHeight = el.height;
	for (let d = el.deps; d !== null; d = d.nextDep) {
		const dep = d.dep;
		if (dep.computed) {
			const depHeight = (dep as Computation).height;
			if (depHeight >= newHeight) { newHeight = depHeight + 1; }
		}
	}
	if (el.height !== newHeight) {
		el.height = newHeight;
		for (let s = el.subs; s !== null; s = s.nextSub) { insertIntoHeapHeight(s.sub); }
	}
}

function visitHeapNode(el: Computation): void {
	if (el.type !== EFFECT_PURE) {
		deleteFromHeap(el);
		el.config = el.config | CONFIG_MODIFIED;
		if (el.type === EFFECT_RENDER) { renderQueue.push(el); } else { userQueue.push(el); }
	} else {
		recompute(el, false);
	}
}

function runHeap(): void {
	heapMarked = false;
	for (heapMin = 0; heapMin <= heapMax; heapMin += 1) {
		let el = heapHead[heapMin];
		while (el !== null) {
			if ((el.flags & REACTIVE_IN_HEAP) !== 0) { visitHeapNode(el); } else { adjustHeight(el); }
			el = heapHead[heapMin];
		}
	}
	heapMax = 0;
}

function enqueueSub(node: Computation): void {
	if (heapMin > node.height) { heapMin = node.height; }
	insertIntoHeap(node);
}

function insertSubs(node: Source): void {
	for (let s = node.subs; s !== null; s = s.nextSub) {
		const sub = s.sub;
		if ((sub.flags & REACTIVE_RECOMPUTING_DEPS) !== 0 && s.gen === sub.depGen && s !== sub.depsTail) {
			sub.flags = sub.flags | REACTIVE_MISSED_WAKE;
		}
		enqueueSub(sub);
	}
}

function unlinkSubs(l: Link): Link | null {
	const dep = l.dep;
	const nextDep = l.nextDep;
	const nextSub = l.nextSub;
	const prevSub = l.prevSub;
	if (nextSub !== null) { nextSub.prevSub = prevSub; } else { dep.subsTail = prevSub; }
	if (prevSub !== null) {
		prevSub.nextSub = nextSub;
	} else {
		dep.subs = nextSub;
		if (nextSub === null && dep.computed) {
			const c = dep as Computation;
			const hook = c.unobserved;
			if (hook !== null) { hook(); }
			if ((c.config & CONFIG_AUTO_DISPOSE) !== 0) { unobserved(c); }
		}
	}
	return nextDep;
}

function trimStaleDeps(el: Computation): void {
	const depsTail = el.depsTail;
	let toRemove = depsTail !== null ? depsTail.nextDep : el.deps;
	if (toRemove !== null) {
		while (toRemove !== null) { toRemove = unlinkSubs(toRemove); }
		if (depsTail !== null) { depsTail.nextDep = null; } else { el.deps = null; }
	}
}

function clearDeps(el: Computation): void {
	let dep = el.deps;
	if (dep === null) { return; }
	while (dep !== null) { dep = unlinkSubs(dep); }
	el.deps = null;
	el.depsTail = null;
}

function unobserved(el: Computation): void {
	deleteFromHeap(el);
	clearDeps(el);
	disposeChildren(el, true);
}

function sweepDormant(): void {
	dormantPending = false;
	if (dormantNodes.length === 0) { return; }
	const nodes = dormantNodes;
	dormantNodes = [];
	for (const el of nodes) {
		el.config = el.config & ~CONFIG_DORMANT_QUEUED;
		if (el.subs === null && (el.config & CONFIG_AUTO_DISPOSE) !== 0 && (el.flags & REACTIVE_DISPOSED) === 0) {
			unobserved(el);
		}
	}
}

function link(dep: Source, sub: Computation): void {
	const prevDep = sub.depsTail;
	if (prevDep !== null && prevDep.dep === dep) { return; }
	let nextDep: Link | null = null;
	const isRecomputing = (sub.flags & REACTIVE_RECOMPUTING_DEPS) !== 0;
	if (isRecomputing) {
		nextDep = prevDep !== null ? prevDep.nextDep : sub.deps;
		if (nextDep !== null && nextDep.dep === dep) {
			nextDep.gen = sub.depGen;
			sub.depsTail = nextDep;
			return;
		}
	}
	const prevSub = dep.subsTail;
	if (prevSub !== null && prevSub.sub === sub && (!isRecomputing || prevSub.gen === sub.depGen)) { return; }
	const newLink: Link = { dep, sub, nextDep, prevSub, nextSub: null, gen: sub.depGen };
	sub.depsTail = newLink;
	dep.subsTail = newLink;
	if (prevDep !== null) { prevDep.nextDep = newLink; } else { sub.deps = newLink; }
	if (prevSub !== null) { prevSub.nextSub = newLink; } else { dep.subs = newLink; }
}

function formatId(prefix: string, index: number): string {
	const digits = index.toString(36);
	const extra = digits.length - 1;
	return prefix + (extra > 0 ? String.fromCharCode(64 + extra) : "") + digits;
}

function idCounter(owner: Computation): Computation {
	let counter = owner;
	while ((counter.config & CONFIG_TRANSPARENT) !== 0 && counter.parent !== null) { counter = counter.parent as Computation; }
	return counter;
}

export function carriesId(owner: Computation | null): boolean {
	return owner !== null && idCounter(owner).id !== null;
}

export function getNextChildId(owner: Computation): string {
	const counter = idCounter(owner);
	const id = counter.id;
	if (id === null) { throw new Error("getNextChildId: the owner carries no id"); }
	const index = counter.childCount;
	counter.childCount = index + 1;
	return formatId(id as string, index);
}

export function inheritId(parent: Computation | null, transparent: boolean): string | null {
	if (parent === null) { return null; }
	if (transparent) { return parent.id; }
	return carriesId(parent) ? getNextChildId(parent) : null;
}

function linkChild(parent: Computation, node: Computation): void {
	const head = parent.firstChild;
	node.prevSibling = null;
	node.nextSibling = head;
	if (head !== null) { head.prevSibling = node; }
	parent.firstChild = node;
}

function runDisposal(node: Computation): void {
	const list = node.disposal;
	if (list === null) { return; }
	node.disposal = null;
	for (let i = list.length - 1; i >= 0; i -= 1) { list[i](); }
}

export function disposeChildren(node: Computation, self: boolean): void {
	const flags = node.flags;
	if ((flags & REACTIVE_DISPOSED) !== 0) { return; }
	if (self) { node.flags = flags | REACTIVE_DISPOSED; }
	let child = node.firstChild;
	node.firstChild = null;
	while (child !== null) {
		child.config = child.config & ~CONFIG_AUTO_DISPOSE;
		deleteFromHeap(child);
		clearDeps(child);
		child.parent = null;
		disposeChildren(child, true);
		const next = child.nextSibling;
		child.nextSibling = null;
		child.prevSibling = null;
		child = next;
	}
	node.childCount = 0;
	const parent = node.parent;
	if (self && parent !== null && (parent.flags & REACTIVE_DISPOSED) === 0) {
		const prev = node.prevSibling;
		const next = node.nextSibling;
		if (prev !== null) { prev.nextSibling = next; } else { parent.firstChild = next; }
		if (next !== null) { next.prevSibling = prev; }
		node.prevSibling = null;
		node.nextSibling = null;
	}
	runDisposal(node);
}

export function disposeNode(node: Computation): void {
	node.config = node.config & ~CONFIG_AUTO_DISPOSE;
	unobserved(node);
	node.parent = null;
	node.run = null;
}

function findHandler(from: Computation | null): ErrorHandler | null {
	let o = from;
	while (o !== null) {
		const h = o.handler;
		if (h !== null) { return h; }
		o = o.parent;
	}
	return null;
}

function nearestComputed(parent: Computation | null): Computation | null {
	if (parent === null) { return null; }
	return (parent.config & CONFIG_ROOT) !== 0 ? parent.parentComputed : parent;
}

function newNode(config: int32, flags: int32, computed: boolean, run: ((self: Computation, create: boolean) => int32) | null, type: int32, parent: Computation | null): Computation {
	return {
		subs: null, subsTail: null, config, computed, commit: null,
		deps: null, depsTail: null, depGen: 0, flags, height: 0, nextHeap: null, prevHeap: null,
		run, type, unobserved: null,
		parent, parentComputed: null, firstChild: null, nextSibling: null, prevSibling: null,
		disposal: null, context: parent !== null ? parent.context : null, handler: null,
		id: null, childCount: 0,
	};
}

export function createOwner(id: string | null = null): Computation {
	const parent = currentOwner;
	const owner = newNode(CONFIG_ROOT, 0, false, null, EFFECT_PURE, parent);
	owner.id = id !== null ? id : inheritId(parent, false);
	owner.parentComputed = nearestComputed(parent);
	if (parent !== null) { linkChild(parent, owner); }
	return owner;
}

export function createComputed(
	run: (self: Computation, create: boolean) => int32,
	type: int32,
	lazy: boolean,
	transparent: boolean,
	unobservedHook: (() => void) | null,
): Computation {
	const parent = currentOwner;
	const config = (transparent ? CONFIG_TRANSPARENT : 0) | (parent === null || lazy ? CONFIG_AUTO_DISPOSE : 0);
	const node = newNode(config, lazy ? REACTIVE_LAZY : 0, true, run, type, parent);
	node.id = inheritId(parent, transparent);
	node.unobserved = unobservedHook;
	node.depsTail = null;
	if (parent !== null) { linkChild(parent, node); }
	const via = nearestComputed(parent);
	if (via !== null) { node.height = via.height + 1; }
	if (!lazy) { recompute(node, true); }
	return node;
}

export function startEffect(node: Computation): void {
	node.config = node.config & ~CONFIG_AUTO_DISPOSE;
	recompute(node, true);
}

export function queueEffect(node: Computation): void {
	node.config = (node.config & ~CONFIG_AUTO_DISPOSE) | CONFIG_MODIFIED;
	enqueueSub(node);
	schedule();
}

function recompute(el: Computation, create: boolean): void {
	if (!create) {
		deleteFromHeap(el);
		disposeChildren(el, false);
	}
	const oldOwner = currentOwner;
	const prevTracking = tracking;
	const oldHeight = el.height;
	currentOwner = el;
	tracking = true;
	deferDepth += 1;
	el.depsTail = null;
	el.depGen = el.depGen + 1;
	el.flags = REACTIVE_RECOMPUTING_DEPS;
	let result: int32 = RUN_UNCHANGED;
	let failure: Error | null = null;
	let missedWake = false;
	try {
		const run = el.run;
		if (run !== null) { result = run(el, create); }
	} catch (e) {
		if (findHandler(el) === null) { throw e; }
		failure = e;
	} finally {
		tracking = prevTracking;
		currentOwner = oldOwner;
		deferDepth -= 1;
		missedWake = (el.flags & REACTIVE_MISSED_WAKE) !== 0;
		el.flags = el.flags & REACTIVE_DISPOSED;
	}
	if (failure !== null) {
		const h = findHandler(el);
		disposeNode(el);
		if (h !== null) { h(failure); }
		return;
	}
	if ((el.flags & REACTIVE_DISPOSED) !== 0) {
		clearDeps(el);
		return;
	}
	if (result !== RUN_UNCHANGED) {
		if (el.subs !== null) { insertSubs(el); }
	} else if (el.height !== oldHeight) {
		for (let s = el.subs; s !== null; s = s.nextSub) { insertIntoHeapHeight(s.sub); }
	}
	trimStaleDeps(el);
	if (result === RUN_STAGED) { stageNode(el); }
	if (missedWake) {
		enqueueSub(el);
		schedule();
	}
	settle();
}

function updateIfNecessary(el: Computation): void {
	if ((el.flags & (REACTIVE_RECOMPUTING_DEPS | REACTIVE_DISPOSED)) !== 0) { return; }
	if ((el.flags & REACTIVE_CHECK) !== 0) {
		for (let d = el.deps; d !== null; d = d.nextDep) {
			const dep = d.dep;
			if (dep.computed) { updateIfNecessary(dep as Computation); }
			if ((el.flags & REACTIVE_DIRTY) !== 0) { break; }
		}
	}
	if ((el.flags & REACTIVE_DIRTY) !== 0) { recompute(el, false); }
	el.flags = el.flags & (REACTIVE_IN_HEAP | REACTIVE_IN_HEAP_HEIGHT | REACTIVE_DISPOSED);
}

function prepareComputed(comp: Computation): void {
	if ((comp.flags & REACTIVE_LAZY) !== 0) {
		comp.flags = comp.flags & ~REACTIVE_LAZY;
		recompute(comp, true);
	} else if ((comp.flags & REACTIVE_DISPOSED) !== 0 && (comp.config & CONFIG_AUTO_DISPOSE) !== 0) {
		const parent = comp.parent;
		if (parent !== null) {
			if ((parent.flags & REACTIVE_DISPOSED) !== 0) {
				comp.config = comp.config & ~CONFIG_AUTO_DISPOSE;
				return;
			}
			linkChild(parent, comp);
		}
		recompute(comp, true);
	}
}

function pullComputed(dep: Computation, c: Computation): void {
	if (dep.height >= heapMin) {
		markNode(c, REACTIVE_DIRTY);
		markHeap();
		updateIfNecessary(dep);
	}
	const height = dep.height;
	if (height >= c.height && dep.parent !== c) { c.height = height + 1; }
}

function serveStaged(el: Source, c: Computation | null): boolean {
	if (c === null || (el.config & CONFIG_STAGED) === 0) { return false; }
	if (unflushedStaged && !running && (el.config & CONFIG_PROMOTED) === 0) {
		c.flags = c.flags | REACTIVE_MISSED_WAKE;
		return false;
	}
	return true;
}

export function readSource(el: Source): boolean {
	let c = currentOwner;
	if (c !== null && (c.config & CONFIG_ROOT) !== 0) { c = c.parentComputed; }
	if (el.computed) { prepareComputed(el as Computation); }
	if (c !== null && tracking) {
		link(el, c);
		if (el.computed) { pullComputed(el as Computation, c); }
	}
	const staged = serveStaged(el, c);
	if (c === null && el.computed && el.subs === null) {
		const comp = el as Computation;
		if ((comp.config & CONFIG_AUTO_DISPOSE) !== 0 && (comp.config & CONFIG_DORMANT_QUEUED) === 0) {
			comp.config = comp.config | CONFIG_DORMANT_QUEUED;
			dormantNodes.push(comp);
			dormantPending = true;
		}
	}
	return staged;
}

function stageNode(el: Source): void {
	el.config = el.config | CONFIG_STAGED;
	pendingNodes.push(el);
	if (!running) { unflushedStaged = true; }
}

export function writeSource(el: Source, wasStaged: boolean): void {
	if (!wasStaged) { stageNode(el); }
	if (currentOwner !== null && !running && (el.config & CONFIG_PROMOTED) === 0) {
		el.config = el.config | CONFIG_PROMOTED;
		promotedWrites.push(el);
	}
	insertSubs(el);
	schedule();
}

function commitPendingNodes(): void {
	const nodes = pendingNodes;
	pendingNodes = [];
	for (const n of nodes) {
		if ((n.config & CONFIG_STAGED) === 0) { continue; }
		n.config = n.config & ~CONFIG_STAGED;
		const commit = n.commit;
		if (commit !== null) { commit(); }
	}
}

function runEffectNode(node: Computation): void {
	if ((node.config & CONFIG_MODIFIED) === 0 || (node.flags & REACTIVE_DISPOSED) !== 0) { return; }
	node.config = node.config & ~CONFIG_MODIFIED;
	recompute(node, false);
}

function runQueue(first: boolean): void {
	const queue = first ? renderQueue : userQueue;
	if (first) { renderQueue = []; } else { userQueue = []; }
	for (let i = 0; i < queue.length; i += 1) { runEffectNode(queue[i]); }
}

function flushOnce(): void {
	if (running) { return; }
	running = true;
	unflushedStaged = false;
	for (const el of promotedWrites) { el.config = el.config & ~CONFIG_PROMOTED; }
	promotedWrites = [];
	const oldOwner = currentOwner;
	const prevTracking = tracking;
	currentOwner = null;
	tracking = false;
	try {
		sweepDormant();
		runHeap();
		commitPendingNodes();
		scheduled = heapMax >= heapMin || pendingNodes.length !== 0;
		runQueue(true);
		runQueue(false);
	} finally {
		running = false;
		currentOwner = oldOwner;
		tracking = prevTracking;
	}
}

export function flush(): void {
	if (running) { return; }
	let rounds: int32 = 0;
	while (scheduled || dormantPending) {
		rounds += 1;
		if (rounds === LOOP_LIMIT) { throw new Error("Potential Infinite Loop Detected. Kept alive by scheduled work"); }
		flushOnce();
	}
}

export function flush<T>(fn: () => T): T {
	syncDepth += 1;
	try {
		return fn();
	} finally {
		try {
			flush();
		} finally {
			syncDepth -= 1;
		}
	}
}

function schedule(): void {
	scheduled = true;
	if (syncDepth === 0 && deferDepth === 0 && !running) {
		// parked: the reference defers this drain with queueMicrotask; ~/metascript/.inbox/compiler/2026-10-15-await-of-a-settled-promise-continues-synchronously-on-c.md
		flush();
	}
}

function settle(): void {
	if (scheduled && syncDepth === 0 && deferDepth === 0 && !running) { flush(); }
}

export function enterRoot(): void { deferDepth += 1; }

export function leaveRoot(completed: boolean): void {
	deferDepth -= 1;
	if (completed) { settle(); }
}
