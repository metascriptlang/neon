import { ErrorHandler } from "./types";
import { createOwner } from "./runtime";
import { runWithOwner } from "./owner";

export function catchError(tryFn: () => void, handler: ErrorHandler): void {
	const scope = createOwner();
	scope.handler = handler;
	try {
		runWithOwner(scope, (): number => { tryFn(); return 0; });
	} catch (e) {
		handler(e);
	}
}
