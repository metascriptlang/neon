import { Computation, Dispose } from "./types";
import { getOwner, setOwner, isTracking, setTracking, createOwner, disposeNode, carriesId, getNextChildId, enterRoot, leaveRoot } from "./runtime";

export function runWithOwner<T>(owner: Computation | null, fn: () => T): T {
	const prevOwner = getOwner();
	const prevTracking = isTracking();
	setOwner(owner);
	setTracking(false);
	try {
		return fn();
	} finally {
		setOwner(prevOwner);
		setTracking(prevTracking);
	}
}

export function createRoot<T>(fn: (dispose: Dispose) => T, id: string | null = null): T {
	const root = createOwner(id);
	const dispose: Dispose = () => { disposeNode(root); };
	enterRoot();
	let completed = false;
	try {
		const result = runWithOwner(root, (): T => fn(dispose));
		completed = true;
		return result;
	} finally {
		leaveRoot(completed);
	}
}

let clientIds: number = 0;

export function createUniqueId(): string {
	const owner = getOwner();
	if (carriesId(owner)) { return getNextChildId(owner as Computation); }
	clientIds += 1;
	return "cl-" + (clientIds - 1).toString();
}
