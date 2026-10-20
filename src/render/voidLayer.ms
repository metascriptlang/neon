import { Host, HostNode, VoidArea } from "./hostTypes";
import { place } from "./reconcile";
import { SPAN_HOST, spanText } from "./spanHost";

function inArea(area: VoidArea, node: HostNode): boolean {
	let at: HostNode | null = node;
	while (at !== null) {
		if (at === area.root) { return true; }
		at = area.host.parentOf(at as HostNode);
	}
	return false;
}

export function layerAnchor(area: VoidArea, host: Host, parent: HostNode, before: HostNode | null): () => boolean {
	if (host !== area.host && host !== SPAN_HOST) {
		throw new Error("a Scene2D or Scene3D mounts on the host of its Void, or inside a Text there");
	}
	const anchor = host.createText("");
	place(host, parent, anchor, before);
	if (host === area.host) { return (): boolean => inArea(area, anchor); }
	return (): boolean => {
		const text = spanText(anchor);
		return text !== null && inArea(area, text as HostNode);
	};
}
