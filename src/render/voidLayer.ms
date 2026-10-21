import { Host, HostNode, VoidArea } from "./hostTypes";
import { place } from "./reconcile";
import { SPAN_HOST } from "./spanHost";
import { LayerAnchor } from "./voidAreaHandle";

export function layerAnchor(area: VoidArea, host: Host, parent: HostNode, before: HostNode | null): LayerAnchor {
	if (host !== area.host && host !== SPAN_HOST) {
		throw new Error("a Scene2D or Scene3D mounts on the host of its Void, or inside a Text there");
	}
	const node = host.createText("");
	place(host, parent, node, before);
	return { node, inText: host === SPAN_HOST };
}
