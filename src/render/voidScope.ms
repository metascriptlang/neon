import { createContext } from "./context";
import { Host, HostNode, VoidArea } from "./hostTypes";
import { place } from "./reconcile";

export enum VoidSpace {
	Outside,
	Area,
	Scene3D,
	Scene2D,
}

export const voidScope = createContext<VoidSpace>(VoidSpace.Outside);
export const voidArea = createContext<VoidArea | null>(null);

export function layerAnchor(area: VoidArea, host: Host, parent: HostNode, before: HostNode | null): () => boolean {
	if (host !== area.host) { return (): boolean => true; }
	const anchor = host.createText("");
	place(host, parent, anchor, before);
	return (): boolean => {
		let at: HostNode | null = anchor;
		while (at !== null) {
			if (at === area.root) { return true; }
			at = area.host.parentOf(at as HostNode);
		}
		return false;
	};
}
