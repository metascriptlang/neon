// Reactive scheduler + graph engine. Holds the thread-local "who is running / who owns"
// state and the dependency-link / dispose primitives. Disposal MUST break links eagerly
// and symmetrically: --gc=drc is ARC-only (no cycle collector), so an undisposed
// Signal<->Computation pair would otherwise leak deterministically.

import { Computation, Source, EffectFn, CompState } from "./types";

let tlListener: Computation | null = null;
let tlOwner: Computation | null = null;
let tlBatchDepth: number = 0;
let tlRunning: boolean = false;
let tlUpdates: Computation[] = [];
let tlEffects: Computation[] = [];

export function getListener(): Computation | null { return tlListener; }
export function setListener(c: Computation | null): void { tlListener = c; }
export function getOwner(): Computation | null { return tlOwner; }
export function setOwner(o: Computation | null): void { tlOwner = o; }
export function getBatchDepth(): number { return tlBatchDepth; }
export function setBatchDepth(d: number): void { tlBatchDepth = d; }

// Link a source and the running computation both ways. Dedup so a signal read twice in
// one run does not accumulate duplicate observer entries.
export function registerDependency(src: Source, l: Computation): void {
	for (const s of l.sources) {
		if (s === src) return;
	}
	const sslot = src.observers.length;
	src.observers.push(l);
	src.observerSlots.push(l.sources.length);
	l.sources.push(src);
	l.sourceSlots.push(sslot);
}

// Remove computation `node` (sitting at source.observers[slot]) from a source.
function removeObserver(source: Source, slot: number): void {
	const last = source.observers.length - 1;
	if (slot > last) return;
	if (slot < last) {
		const movedComp = source.observers[last];
		const movedSlot = source.observerSlots[last];
		source.observers[slot] = movedComp;
		source.observerSlots[slot] = movedSlot;
		movedComp.sourceSlots[movedSlot] = slot;
	}
	source.observers.pop();
	source.observerSlots.pop();
}

// Remove the source sitting at observer.sources[slot] from a downstream observer
// (used when a memo node — itself a Source — is disposed).
function removeSourceFromObserver(obs: Computation, slot: number): void {
	const last = obs.sources.length - 1;
	if (slot > last) return;
	if (slot < last) {
		const movedSrc = obs.sources[last];
		const movedSlot = obs.sourceSlots[last];
		obs.sources[slot] = movedSrc;
		obs.sourceSlots[slot] = movedSlot;
		movedSrc.observerSlots[movedSlot] = slot;
	}
	obs.sources.pop();
	obs.sourceSlots.pop();
}

// The one teardown primitive. dispose=false → re-track prep (clear deps + run cleanups,
// keep node alive). dispose=true → full teardown. Breaks BOTH halves of every cycle.
export function cleanNode(node: Computation, dispose: boolean): void {
	if (dispose) { node.disposed = true; }

	for (let i = node.owned.length - 1; i >= 0; i -= 1) {
		cleanNode(node.owned[i], true);
	}
	node.owned = [];

	for (let i = 0; i < node.sources.length; i += 1) {
		removeObserver(node.sources[i], node.sourceSlots[i]);
	}
	node.sources = [];
	node.sourceSlots = [];

	for (let i = 0; i < node.observers.length; i += 1) {
		removeSourceFromObserver(node.observers[i], node.observerSlots[i]);
	}
	node.observers = [];
	node.observerSlots = [];

	for (let i = node.cleanups.length - 1; i >= 0; i -= 1) {
		node.cleanups[i]();
	}
	node.cleanups = [];
}

export function createComputation(fn: EffectFn, pure: boolean): Computation {
	const comp: Computation = {
		observers: [], observerSlots: [],
		fn, isRoot: false, state: CompState.Stale,
		sources: [], sourceSlots: [],
		pure, disposed: false,
		owned: [], cleanups: [], owner: tlOwner,
	};
	if (tlOwner !== null) { tlOwner.owned.push(comp); }
	return comp;
}

export function runComputation(comp: Computation): void {
	if (comp.disposed) return;
	cleanNode(comp, false);
	comp.state = CompState.Clean;
	const prevListener = tlListener;
	const prevOwner = tlOwner;
	tlListener = comp;
	tlOwner = comp;
	comp.fn();
	tlListener = prevListener;
	tlOwner = prevOwner;
}

export function updateComputation(comp: Computation): void {
	if (comp.disposed) return;
	if (comp.state === CompState.Clean) return;
	runComputation(comp);
}

// Enqueue a marked observer for the next drain.
export function enqueue(comp: Computation): void {
	if (comp.pure) { tlUpdates.push(comp); } else { tlEffects.push(comp); }
}

// Drain pure (memos) then effects, re-entrancy-guarded. The queues may grow mid-drain
// (an effect writing a signal), so this is a genuine condition-driven loop.
export function runQueue(): void {
	if (tlRunning) return;
	tlRunning = true;
	let guard = 0;
	while ((tlUpdates.length > 0 || tlEffects.length > 0) && guard < 1000000) {
		guard += 1;
		if (tlUpdates.length > 0) {
			const c = tlUpdates[tlUpdates.length - 1];
			tlUpdates.pop();
			updateComputation(c);
		} else {
			const c = tlEffects[tlEffects.length - 1];
			tlEffects.pop();
			updateComputation(c);
		}
	}
	tlRunning = false;
}
