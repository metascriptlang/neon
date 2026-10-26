import { Host, HostNode, NeonNode } from "./hostTypes";
import { Computation, Dispose } from "../core/types";
import { getOwner, flush } from "../core/runtime";
import { setSnapshotCapture, markSnapshotScope, releaseSnapshotScope, clearSnapshots } from "../core/snapshotScope";
import { render } from "./host";
import { beginClaim, claimRefusal, endClaim } from "./claim";
import { lazyLoaded, preloadLazy } from "./lazy";
import { moduleKeys } from "./hydrationRecords";

function cleared(host: Host, container: HostNode): void {
	let child = host.firstChild(container);
	while (child !== null) {
		host.removeChild(container, child as HostNode);
		child = host.firstChild(container);
	}
}

class HeldWrites {
	scope: Computation | null = null;
}

function heldUnderRoot(node: NeonNode, held: HeldWrites): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const root = getOwner() as Computation;
		markSnapshotScope(root);
		held.scope = root;
		node(host, parent, before);
	};
}

function releaseHeld(held: HeldWrites): void {
	const scope = held.scope;
	held.scope = null;
	if (scope !== null) { releaseSnapshotScope(scope); }
	clearSnapshots();
}

function claimPass(node: NeonNode, host: Host, container: HostNode): Dispose {
	beginClaim(host, container);
	const held = new HeldWrites();
	setSnapshotCapture(true);
	try {
		const dispose = render(heldUnderRoot(node, held), host, container, "");
		let refused: string | null = null;
		try {
			refused = claimRefusal(host);
		} catch (error) {
			dispose();
			throw error;
		}
		if (refused === null) { return dispose; }
		dispose();
		cleared(host, container);
		console.error(refused as string);
		return render(node, host, container, "");
	} finally {
		endClaim(host);
		releaseHeld(held);
	}
}

function claimServed(node: NeonNode, host: Host, container: HostNode): Dispose {
	const dispose = claimPass(node, host, container);
	try {
		flush();
	} catch (error) {
		dispose();
		throw error;
	}
	return dispose;
}

class PendingHydrate {
	cancelled: boolean = false;
	mounted: Dispose | null = null;
}

export function hydrate(node: NeonNode, host: Host, container: HostNode): Dispose {
	const keys = moduleKeys();
	if (lazyLoaded(keys)) { return claimServed(node, host, container); }
	const pending = new PendingHydrate();
	preloadLazy(keys).then((): void => {
		if (!pending.cancelled) { pending.mounted = claimServed(node, host, container); }
	}, (error: Error): void => {
		console.error("hydrate: a lazy module the page lists did not load, so the page renders fresh: " + error.message);
		if (pending.cancelled) { return; }
		cleared(host, container);
		pending.mounted = render(node, host, container, "");
	});
	return (): void => {
		pending.cancelled = true;
		if (pending.mounted !== null) { (pending.mounted as Dispose)(); }
	};
}
