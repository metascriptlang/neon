import { Style } from "../render/style";
import { Accessor } from "../core/signal";
import { NeonNode, VAttr } from "../render/node";
import { stringAttr } from "./primitives";
import { Host, HostNode } from "../render/hostTypes";
import { portalNode } from "../render/portal";

when (c && !server && ios) {
	import "../platform/native/inputAccessoryView";
}

interface InputAccessoryViewProps {
	nativeID?: Accessor<string> | null;
	backgroundColor?: Accessor<string> | null;
	style?: Accessor<Style> | null;
	children?: NeonNode | null;
}

const nothing: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {};

// RN InputAccessoryView lays its children out in a view of the window's width and hands that
// view to UIKit as the keyboard's accessory (iOS only). The children go through a Portal into
// the host's overlay root, in an "inputaccessoryview" node that spans the width, as Modal does;
// the iOS host moves the node's views into the accessory.
export function inputAccessoryViewNode(props: InputAccessoryViewProps): NeonNode {
	if (props.children === null) { return nothing; }
	const { nativeID, backgroundColor, style } = props;
	const box = (): Style => {
		const own: Style = style === null ? {} : (style as Accessor<Style>)();
		return { ...own, position: "absolute", top: 0, left: 0, right: 0 };
	};
	const attrs: VAttr[] = [];
	stringAttr(attrs, "nativeID", nativeID);
	stringAttr(attrs, "backgroundColor", backgroundColor);
	return portalNode(null, "inputaccessoryview", attrs, [], box, props.children);
}

when (ios) {
	export function InputAccessoryView(props: InputAccessoryViewProps): NeonNode {
		return inputAccessoryViewNode(props);
	}
} else {
	export function InputAccessoryView(props: InputAccessoryViewProps): NeonNode {
		return nothing;
	}
}
