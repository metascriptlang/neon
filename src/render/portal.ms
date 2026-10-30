import { onCleanup } from "../core/cleanup";
import { getOwner, createOwner } from "../core/runtime";
import { runWithOwner } from "../core/owner";
import { Accessor } from "../core/signal";
import { Style } from "./style";
import { NeonNode, VAttr, VEvent, hostElement } from "./node";
import { Host, HostNode } from "./hostTypes";
import { createContext, setContext, useContext } from "./context";
import { unclaimed } from "./claim";
import { makeRow, mountApart } from "./reconcile";

interface PortalProps {
	mount?: HostNode | null;
	style?: Accessor<Style> | null;
	children?: NeonNode | null;
}

// Solid's <Portal>: the children mount into a container appended to another
// node — `mount`, or the host's overlay root — while they stay in this owner,
// so context and cleanup follow the Portal's place in the tree.
export function Portal(props: PortalProps): NeonNode {
	const style = props.style;
	const paint = style === null ? null : (): Style => (style as Accessor<Style>)();
	return portalNode(props.mount, "view", [], [], paint, props.children);
}

// RN's Modal presents its whole subtree in its own window, so an overlay opened
// inside one lands in that window: a portal under a "modal" container targets it.
const EnclosingModal = createContext<HostNode | null>(null);

export function portalNode(
	mount: HostNode | null,
	tag: string,
	attrs: VAttr[],
	events: VEvent[],
	style: (() => Style) | null,
	children: NeonNode | null,
): NeonNode {
	const content: NeonNode | null = children === null || tag !== "modal" ? children : (h: Host, node: HostNode, at: HostNode | null): void => {
		const scope = createOwner();
		runWithOwner(scope, (): number => {
			setContext(EnclosingModal, node);
			(children as NeonNode)(h, node, at);
			return 0;
		});
	};
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		let target: HostNode;
		if (mount !== null) {
			target = mount as HostNode;
		} else {
			const modal = getOwner() === null ? null : useContext(EnclosingModal);
			if (modal !== null) {
				target = modal as HostNode;
			} else {
				const layer = host.overlayRoot;
				if (layer === null) { throw "<Portal> without a mount node needs a host with the overlayRoot capability, and this host has none"; }
				target = (layer as (n: HostNode) => HostNode)(parent);
			}
		}
		let container: HostNode | null = null;
		const grab = (node: HostNode): void => { container = node; };
		const physical = makeRow(hostElement(tag, attrs, events, content, style, grab));
		unclaimed(host, (): void => { mountApart(host, target, null, physical); });
		onCleanup((): void => {
			if (container !== null) { host.removeChild(target, container as HostNode); }
		});
	};
}
