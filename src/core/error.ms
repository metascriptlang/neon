import { Computation, CompState, ErrorHandler } from "./types";
import { getOwner, inheritId } from "./runtime";
import { runWithOwner } from "./owner";

function noop(): void {}

export function catchError(tryFn: () => void, handler: ErrorHandler): void {
	const parent = getOwner();
	const scope: Computation = {
		observers: [], observerSlots: [],
		fn: noop, isRoot: false, state: CompState.Clean,
		sources: [], sourceSlots: [],
		pure: false, user: false, disposed: false,
		owned: [], cleanups: [], owner: parent, context: parent !== null ? parent.context : null, handler: handler,
		id: inheritId(parent, false), childCount: 0, transparent: false,
	};
	if (parent !== null) { parent.owned.push(scope); }
	try {
		runWithOwner(scope, (): number => { tryFn(); return 0; });
	} catch (e) {
		handler(e);
	}
}
