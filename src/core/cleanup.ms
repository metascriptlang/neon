// Cleanup - Disposal Management
// Register cleanup functions that run when effect is disposed

let cleanupStack: (() => void)[][] = [];

export function onCleanup(fn: () => void): void {
	if (cleanupStack.length === 0) {
		throw new Error("onCleanup called outside of effect");
	}

	const current = cleanupStack[cleanupStack.length - 1];
	current.push(fn);
}

export function pushCleanupScope(): void {
	cleanupStack.push([]);
}

export function popCleanupScope(): void {
	const cleanups = cleanupStack.pop();
	if (cleanups) {
		cleanups.forEach(cleanup => cleanup());
	}
}
