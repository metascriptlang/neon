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
		owned: [], cleanups: [], owner: null,
	};
	const prevOwner = getOwner();
	const prevListener = getListener();
	setOwner(root);
	setListener(null);
	const dispose: Dispose = () => { cleanNode(root, true); };
	const result = fn(dispose);
	setOwner(prevOwner);
	setListener(prevListener);
	return result;
}

export function runWithOwner<T>(owner: Computation | null, fn: () => T): T {
	const prev = getOwner();
	setOwner(owner);
	const result = fn();
	setOwner(prev);
	return result;
}
