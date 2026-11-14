import { Host, HostNode } from "../../src/render/host";
import { NeonNode } from "../../src/render/node";
import { TextSpan } from "../../src/render/hostTypes";
import { spanParagraph } from "../../src/render/spanHost";
import { Accessor } from "../../src/core/signal";
import { Style } from "../../src/render/style";
import { NeonEvent, neonEvent, eventType } from "../../src/render/event";

extern function uiCreateElement(tag: string): int32 from "ui.createElement";
extern function uiCreateText(s: string): int32 from "ui.createText";
extern function uiSetText(node: int32, s: string): void from "ui.setText";
extern function uiSetAttr(node: int32, name: string, value: string): void from "ui.setAttr";
extern function uiRemoveAttr(node: int32, name: string): void from "ui.removeAttr";
extern function uiSetStyle(node: int32, style: Style): void from "ui.setStyle";
extern function uiAddEvent(node: int32, name: string, handler: int32): void from "ui.addEvent";
extern function uiAppend(parent: int32, child: int32): void from "ui.append";
extern function uiInsertBefore(parent: int32, node: int32, before: int32): void from "ui.insertBefore";
extern function uiRemoveChild(parent: int32, node: int32): void from "ui.removeChild";
extern function uiParentOf(node: int32): int32 from "ui.parentOf";
extern function uiRelease(node: int32): void from "ui.release";
extern function uiNextSibling(node: int32): int32 from "ui.nextSibling";
extern function uiFirstChild(node: int32): int32 from "ui.firstChild";
extern function uiSetSpans(node: int32, texts: string[]): void from "ui.setSpans";

class Remote {
	id: int32;
	constructor(id: int32) { this.id = id; }
}

const remotes: (Remote | null)[] = [];
const handlers: ((e: NeonEvent) => void)[] = [];
const handlerNames: string[] = [];

export function remoteOf(id: int32): HostNode | null {
	if (id < 0) { return null; }
	while (remotes.length <= id) { remotes.push(null); }
	let r = remotes[id];
	if (r === null) {
		r = new Remote(id);
		remotes[id] = r;
	}
	return r as unknown as HostNode;
}

function idOf(node: HostNode | null): int32 {
	return node === null ? -1 : (node as unknown as Remote).id;
}

function deliver(node: HostNode, spans: TextSpan[]): void {
	uiSetSpans(idOf(node), spans.map((s: TextSpan): string => s.text));
}

export function handlerCount(): int32 {
	return handlers.length as int32;
}

export function fire(handler: int32, x: number, y: number, timeStamp: number, button: number, pressed: boolean, pointerOrigin: boolean): void {
	const e = neonEvent(eventType(handlerNames[handler]));
	e.x = x;
	e.y = y;
	e.timeStamp = timeStamp;
	e.button = button;
	e.pressed = pressed;
	e.pointerOrigin = pointerOrigin;
	handlers[handler](e);
}

export function bridgeHost(paragraphs: boolean): Host {
	return {
		createElement: (tag: string): HostNode => remoteOf(uiCreateElement(tag)) as HostNode,
		createText: (s: string): HostNode => remoteOf(uiCreateText(s)) as HostNode,
		setText: (node: HostNode, s: string): void => { uiSetText(idOf(node), s); },
		setAttr: (node: HostNode, name: string, value: string): void => { uiSetAttr(idOf(node), name, value); },
		removeAttr: (node: HostNode, name: string): void => { uiRemoveAttr(idOf(node), name); },
		setStyle: (node: HostNode, style: Style): void => { uiSetStyle(idOf(node), style); },
		setStyleProp: null,
		setStyleClass: null,
		addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {
			handlers.push(handler);
			handlerNames.push(name);
			uiAddEvent(idOf(node), name, (handlers.length - 1) as int32);
		},
		append: (parent: HostNode, child: HostNode): void => { uiAppend(idOf(parent), idOf(child)); },
		insertBefore: (parent: HostNode, node: HostNode, before: HostNode | null): void => {
			uiInsertBefore(idOf(parent), idOf(node), idOf(before));
		},
		removeChild: (parent: HostNode, node: HostNode): void => { uiRemoveChild(idOf(parent), idOf(node)); },
		parentOf: (node: HostNode): HostNode | null => remoteOf(uiParentOf(idOf(node))),
		release: (node: HostNode): void => { uiRelease(idOf(node)); },
		nextSibling: (node: HostNode): HostNode | null => remoteOf(uiNextSibling(idOf(node))),
		firstChild: (node: HostNode): HostNode | null => remoteOf(uiFirstChild(idOf(node))),
		cloneNode: null,
		voidArea: null,
		scrollTo: null,
		measureText: null,
		paragraph: paragraphs ? (host: Host, node: HostNode, before: HostNode | null, kids: NeonNode | null, spans: Accessor<TextSpan[]> | null): void => {
			spanParagraph(deliver, node, kids, spans);
		} : null,
	};
}
