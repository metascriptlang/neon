import { onCleanup } from "../core/cleanup";
import { Style } from "./style";
import { NeonNode, VAttr, VEvent, hostElement } from "./node";
import { Host, HostNode } from "./hostTypes";

interface PortalProps {
	mount?: HostNode | null;
	children?: NeonNode | null;
}

// Solid's <Portal>: the children mount into a container appended to another
// node — `mount`, or the host's overlay root — while they stay in this owner,
// so context and cleanup follow the Portal's place in the tree.
export function Portal(props: PortalProps): NeonNode {
	return portalNode(props.mount, "view", [], [], null, props.children);
}

export function portalNode(
	mount: HostNode | null,
	tag: string,
	attrs: VAttr[],
	events: VEvent[],
	style: (() => Style) | null,
	children: NeonNode | null,
): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		let target: HostNode;
		if (mount !== null) {
			target = mount as HostNode;
		} else {
			const layer = host.overlayRoot;
			if (layer === null) { throw "<Portal> without a mount node needs a host with the overlayRoot capability, and this host has none"; }
			target = (layer as (n: HostNode) => HostNode)(parent);
		}
		let container: HostNode | null = null;
		const grab = (node: HostNode): void => { container = node; };
		hostElement(tag, attrs, events, children, style, grab)(host, target, null);
		onCleanup((): void => {
			if (container !== null) { host.removeChild(target, container as HostNode); }
		});
	};
}
