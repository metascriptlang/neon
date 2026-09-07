// Owner — disposal scope. createRoot establishes a detached owner whose dispose tears
// down every computation created under it (cascading through the owned tree).

import { Computation, Dispose, CompState } from "./types";
import { getOwner, setOwner, getListener, setListener, cleanNode } from "./runtime";

function noop(): void {}

export function createRoot<T>(fn: (dispose: Dispose) => T): T {
	const root: Computation = {
		observers: [], observerSlots: [],
		fn: noop, isRoot: true, state: CompState.Clean,
		sources: [], sourceSlots: [],
		pure: false, disposed: false,
		owned: [], cleanups: [], owner: null, contexts: null,
	};
	const prevOwner = getOwner();
	const prevListener = getListener();
	setOwner(root);
	setListener(null);
	const dispose: Dispose = () => { cleanNode(root, true); };
	try {
		return fn(dispose);
	} finally {
		setOwner(prevOwner);
		setListener(prevListener);
	}
}

export function runWithOwner<T>(owner: Computation | null, fn: () => T): T {
	const prev = getOwner();
	setOwner(owner);
	try {
		return fn();
	} finally {
		setOwner(prev);
	}
}
