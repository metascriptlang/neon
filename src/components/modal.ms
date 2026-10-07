import { Style } from "../render/style";
import { NeonEvent } from "../render/event";
import { Accessor, accessor } from "../core/signal";
import { onCleanup } from "../core/cleanup";
import { element } from "../macros/ui/element";
import { Show } from "../macros/ui/flow";
import { NeonNode, VAttr, VEvent, dynAttr, evt } from "../render/node";
import { Host, HostNode } from "../render/hostTypes";
import { portalNode } from "../render/portal";

export type ModalAnimationType = "none" | "slide" | "fade";

interface ModalProps {
	visible?: Accessor<boolean> | null;
	animationType?: Accessor<ModalAnimationType> | null;
	transparent?: Accessor<boolean> | null;
	onRequestClose?: (() => void) | null;
	onShow?: (() => void) | null;
	onDismiss?: (() => void) | null;
	children?: NeonNode | null;
}

// An opaque Modal paints the root's own background: black on the native hosts,
// whose default text is white, and white in the browser.
when (js) {
	const OPAQUE = "#ffffff";
} else {
	const OPAQUE = "#000000";
}

// RN Modal presents its children above the whole app (a new view controller on
// iOS, a Dialog on Android). Here the children go through a Portal into the
// host's overlay root, in a "modal" node that fills it and stacks above the app.
export function Modal(props: ModalProps): NeonNode {
	const { visible, animationType, transparent, onRequestClose, onShow, onDismiss } = props;
	const shown = accessor((): boolean => visible === null || (visible as Accessor<boolean>)());
	const style = accessor((): Style => ({
		position: "absolute", top: 0, left: 0, right: 0, bottom: 0, zIndex: 1000,
		backgroundColor: transparent !== null && (transparent as Accessor<boolean>)() ? "transparent" : OPAQUE,
	}));
	const attrs: VAttr[] = [];
	if (animationType !== null) {
		const read = animationType as Accessor<ModalAnimationType>;
		attrs.push(dynAttr("animationType", (): string | null => { const t: ModalAnimationType = read(); return t; }));
	}
	const events: VEvent[] = [];
	if (onRequestClose !== null) {
		events.push(evt("onRequestClose", (e: NeonEvent): void => { (onRequestClose as () => void)(); }));
	}
	const sheet = portalNode(null, "modal", attrs, events, style as () => Style, props.children);
	const presented: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		sheet(host, parent, before);
		if (onShow !== null) { setTimeout((): void => { (onShow as () => void)(); }, 0); }
		if (onDismiss !== null) {
			onCleanup((): void => { setTimeout((): void => { (onDismiss as () => void)(); }, 0); });
		}
	};
	return element(<Show when={shown()}>{presented}</Show>);
}
