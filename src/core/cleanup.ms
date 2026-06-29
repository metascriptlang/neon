// Cleanup — register a disposer that runs when the current computation re-runs or is
// disposed. Registers into the owning computation's cleanup list (run by cleanNode),
// replacing the old standalone scope stack that createEffect never pushed.

import { getOwner } from "./runtime";

export function onCleanup(fn: () => void): void {
	const o = getOwner();
	if (o !== null) { o.cleanups.push(fn); }
}
