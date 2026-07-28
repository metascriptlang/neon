import { Style } from "./style";

export type HostNode = unknown;

export interface Host {
	createElement: (tag: string) => HostNode;
	createText: (s: string) => HostNode;
	setText: (node: HostNode, s: string) => void;
	setAttr: (node: HostNode, name: string, value: string) => void;
	setStyle: (node: HostNode, style: Style) => void;
	addEvent: (node: HostNode, name: string, handler: () => void) => void;
	append: (parent: HostNode, child: HostNode) => void;
	insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null) => void;
	removeChild: (parent: HostNode, node: HostNode) => void;
	nextSibling: (node: HostNode) => HostNode | null;
}
