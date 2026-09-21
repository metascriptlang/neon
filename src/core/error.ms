import { Computation, CompState, ErrorHandler } from "./types";
import { getOwner } from "./runtime";
import { runWithOwner } from "./owner";

function noop(): void {}

export function catchError(tryFn: () => void, handler: ErrorHandler): void {
	const parent = getOwner();
	const scope: Computation = {
		observers: [], observerSlots: [],
		fn: noop, isRoot: false, state: CompState.Clean,
		sources: [], sourceSlots: [],
		pure: false, disposed: false,
		owned: [], cleanups: [], owner: parent, contexts: null, handler: handler,
	};
	if (parent !== null) { parent.owned.push(scope); }
	try {
		runWithOwner(scope, (): number => { tryFn(); return 0; });
	} catch (e) {
		handler(e.message);
	}
}
