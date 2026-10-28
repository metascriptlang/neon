import { onCleanup } from "../core/cleanup";
import { Host, HostNode, NeonNode } from "./hostTypes";
import { makeRow, mountApart, removeRow } from "./reconcile";
import { unclaimed } from "./claim";

interface HeadProps {
	children?: NeonNode | null;
}

export function Head(props: HeadProps): NeonNode {
	const children = props.children;
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const rootOf = host.headRoot;
		if (rootOf === null || children === null) { return; }
		const head = (rootOf as (n: HostNode) => HostNode)(parent);
		const row = makeRow(children as NeonNode);
		unclaimed(host, (): void => { mountApart(host, head, host.firstChild(head), row); });
		onCleanup((): void => { removeRow(host, head, row); });
	};
}
