// Owner — disposal scope. createRoot establishes an owner whose dispose tears down every
// computation created under it (cascading through the owned tree). It links to the owner it
// was created under for the context walk, but stays out of that owner's `owned`.

import { Computation, Dispose, CompState } from "./types";
import { getOwner, setOwner, getListener, setListener, cleanNode } from "./runtime";

function noop(): void {}

export function createRoot<T>(fn: (dispose: Dispose) => T): T {
	const prevOwner = getOwner();
	const prevListener = getListener();
	const root: Computation = {
		observers: [], observerSlots: [],
		fn: noop, isRoot: true, state: CompState.Clean,
		sources: [], sourceSlots: [],
		pure: false, disposed: false,
		owned: [], cleanups: [], owner: prevOwner, contexts: null,
	};
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
