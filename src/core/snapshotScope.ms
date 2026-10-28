import { Source, Computation, CONFIG_HAS_SNAPSHOT, CONFIG_IN_SNAPSHOT_SCOPE, CONFIG_SNAPSHOT_SCOPE, REACTIVE_SNAPSHOT_STALE } from "./types";
import { SnapshotStore, setSnapshotStore, wakeNode, requestFlush } from "./runtime";

class Snapshots {
	sources: Source[] = [];
	cells: Map<unknown, unknown> = new Map<unknown, unknown>();
}

let held: Snapshots | null = null;

function snapshotsHeld(): Snapshots {
	const s = held;
	if (s === null) { throw new Error("[SNAPSHOT_WITHOUT_CAPTURE] the hydration capture holds no snapshots"); }
	return s;
}

const store: SnapshotStore = {
	keep: (el: Source, cell: unknown): void => {
		const s = snapshotsHeld();
		s.sources.push(el);
		s.cells.set(el as unknown, cell);
	},
	kept: (el: Source): unknown => snapshotsHeld().cells.get(el as unknown),
};

export function setSnapshotCapture(active: boolean): void {
	if (active && held === null) { held = new Snapshots(); }
	setSnapshotStore(active ? store : null);
}

export function markSnapshotScope(owner: Computation): void {
	owner.config = owner.config | CONFIG_SNAPSHOT_SCOPE;
}

function releaseSubtree(owner: Computation): void {
	let child = owner.firstChild;
	while (child !== null) {
		if ((child.config & CONFIG_SNAPSHOT_SCOPE) === 0) {
			if (child.computed) {
				child.config = child.config & ~CONFIG_IN_SNAPSHOT_SCOPE;
				if ((child.flags & REACTIVE_SNAPSHOT_STALE) !== 0) {
					child.flags = child.flags & ~REACTIVE_SNAPSHOT_STALE;
					wakeNode(child);
				}
			}
			releaseSubtree(child);
		}
		child = child.nextSibling;
	}
}

export function releaseSnapshotScope(owner: Computation): void {
	owner.config = owner.config & ~CONFIG_SNAPSHOT_SCOPE;
	releaseSubtree(owner);
	requestFlush();
}

export function clearSnapshots(): void {
	const s = held;
	held = null;
	if (s !== null) {
		for (const source of s.sources) { source.config = source.config & ~CONFIG_HAS_SNAPSHOT; }
	}
	setSnapshotStore(null);
}
