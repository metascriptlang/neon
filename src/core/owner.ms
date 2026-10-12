// Owner — disposal scope. createRoot establishes an owner whose dispose tears down every
// computation created under it (cascading through the owned tree).

import { Computation, Dispose, CompState } from "./types";
import { getOwner, setOwner, getListener, setListener, cleanNode, carriesId, getNextChildId, inheritId } from "./runtime";

function noop(): void {}

export function createRoot<T>(fn: (dispose: Dispose) => T, id: string | null = null): T {
	const prevOwner = getOwner();
	const prevListener = getListener();
	const root: Computation = {
		observers: [], observerSlots: [],
		fn: noop, isRoot: true, state: CompState.Clean,
		sources: [], sourceSlots: [],
		pure: false, disposed: false,
		owned: [], cleanups: [], owner: prevOwner, context: prevOwner !== null ? prevOwner.context : null, handler: null,
		id: id !== null ? id : inheritId(prevOwner, false), childCount: 0, transparent: false,
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

let clientIds: number = 0;

export function createUniqueId(): string {
	const owner = getOwner();
	if (carriesId(owner)) { return getNextChildId(owner as Computation); }
	clientIds += 1;
	return "cl-" + (clientIds - 1).toString();
}
