import {
	Host, HostNode, NeonNode, TextSpan, TextMeasure, MeasureRect, MeasureError,
} from "../../render/hostTypes";
import { spanParagraph } from "../../render/spanHost";
import { Style } from "../../render/style";
import { NeonEvent } from "../../render/event";
import { Accessor } from "../../core/signal";
import { createRoot } from "../../core/owner";
import { flush } from "../../core/runtime";
import { Dispose } from "../../core/types";
import {
	NO_NODE, NO_HANDLER, REGION, REGION_END, MEASURE_ERRORS,
	CAN_PARAGRAPH, CAN_FOCUS, CAN_SCROLL_TO, CAN_MEASURE_TEXT, CAN_MEASURE_IN_WINDOW, CAN_MEASURE_LAYOUT,
	can, handleIndex,
} from "./wire";

extern function uiCapabilities(root: int32): int32 from "ui.capabilities";
extern function uiCreateElement(root: int32, tag: string): int32 from "ui.createElement";
extern function uiCreateText(root: int32, s: string): int32 from "ui.createText";
extern function uiSetText(root: int32, node: int32, s: string): void from "ui.setText";
extern function uiSetAttr(root: int32, node: int32, name: string, value: string): void from "ui.setAttr";
extern function uiRemoveAttr(root: int32, node: int32, name: string): void from "ui.removeAttr";
extern function uiSetStyle(root: int32, node: int32, style: Style): void from "ui.setStyle";
extern function uiAddEvent(root: int32, node: int32, name: string, handler: int32): void from "ui.addEvent";
extern function uiAppend(root: int32, parent: int32, child: int32): void from "ui.append";
extern function uiInsertBefore(root: int32, parent: int32, node: int32, before: int32): void from "ui.insertBefore";
extern function uiRemoveChild(root: int32, parent: int32, node: int32): int32[] from "ui.removeChild";
extern function uiRelease(root: int32, node: int32): int32[] from "ui.release";
extern function uiParentOf(root: int32, node: int32): int32 from "ui.parentOf";
extern function uiNextSibling(root: int32, node: int32): int32 from "ui.nextSibling";
extern function uiFirstChild(root: int32, node: int32): int32 from "ui.firstChild";
extern function uiSetSpans(
	root: int32, node: int32, texts: string[], styles: (Style | null)[], presses: int32[], touches: int32[],
): void from "ui.setSpans";
extern function uiFocus(root: int32, node: int32, focused: boolean): void from "ui.focus";
extern function uiScrollTo(root: int32, node: int32, x: number, y: number, animated: boolean): void from "ui.scrollTo";
extern function uiMeasureText(root: int32, text: string, style: Style): number[] from "ui.measureText";
extern function uiMeasure(root: int32, node: int32, ancestor: int32): number[] from "ui.measure";

type Handler = (name: string, e: NeonEvent) => void;

class Remote {
	handle: int32;

	constructor(handle: int32) {
		this.handle = handle;
	}
}

class GuestRoot {
	key: int32;
	remotes: (Remote | null)[] = [];
	handlers: (Handler | null)[] = [];
	idleHandlers: int32[] = [];
	nodeHandlers: Map<int32, int32[]> = new Map<int32, int32[]>();
	spanHandlers: Map<int32, int32[]> = new Map<int32, int32[]>();
	dispose: Dispose | null = null;

	constructor(key: int32) {
		this.key = key;
	}
}

const roots = new Map<int32, GuestRoot>();

function rootAt(key: int32): GuestRoot {
	const r = roots.get(key);
	if (r === undefined) { throw new Error(`no guest root ${key} is mounted in this program`); }
	return r;
}

function remote(r: GuestRoot, handle: int32): HostNode | null {
	if (handle === NO_NODE) { return null; }
	const at = handleIndex(handle);
	while (r.remotes.length <= at) { r.remotes.push(null); }
	const known = r.remotes[at];
	if (known !== null && known.handle === handle) { return known as unknown as HostNode; }
	const made = new Remote(handle);
	r.remotes[at] = made;
	return made as unknown as HostNode;
}

function handleOf(node: HostNode | null): int32 {
	return node === null ? NO_NODE : (node as unknown as Remote).handle;
}

function keep(r: GuestRoot, owned: int32[], handler: Handler): int32 {
	let id = r.handlers.length as int32;
	if (r.idleHandlers.length > 0) {
		id = r.idleHandlers.pop() as int32;
		r.handlers[id] = handler;
	} else {
		r.handlers.push(handler);
	}
	owned.push(id);
	return id;
}

function dropHandlers(r: GuestRoot, table: Map<int32, int32[]>, handle: int32): void {
	const ids = table.get(handle);
	if (ids === undefined) { return; }
	for (const id of ids) {
		r.handlers[id] = null;
		r.idleHandlers.push(id);
	}
	table.delete(handle);
}

function dropFreed(r: GuestRoot, freed: int32[]): void {
	for (const handle of freed) {
		const at = handleIndex(handle);
		if (at < r.remotes.length) { r.remotes[at] = null; }
		dropHandlers(r, r.nodeHandlers, handle);
		dropHandlers(r, r.spanHandlers, handle);
	}
}

function eventHandler(handler: (e: NeonEvent) => void): Handler {
	return (name: string, e: NeonEvent): void => { handler(e); };
}

function addHandler(r: GuestRoot, node: HostNode, name: string, handler: (e: NeonEvent) => void): void {
	const handle = handleOf(node);
	let owned = r.nodeHandlers.get(handle);
	if (owned === undefined) {
		owned = [];
		r.nodeHandlers.set(handle, owned);
	}
	uiAddEvent(r.key, handle, name, keep(r, owned, eventHandler(handler)));
}

function deliver(r: GuestRoot, node: HostNode, spans: TextSpan[]): void {
	const handle = handleOf(node);
	dropHandlers(r, r.spanHandlers, handle);
	const owned: int32[] = [];
	const texts: string[] = [];
	const styles: (Style | null)[] = [];
	const presses: int32[] = [];
	const touches: int32[] = [];
	for (const span of spans) {
		texts.push(span.text);
		styles.push(span.style ?? null);
		const press = span.onPress ?? null;
		presses.push(press === null ? NO_HANDLER : keep(r, owned, eventHandler(press)));
		const touch = span.onTouch ?? null;
		touches.push(touch === null ? NO_HANDLER : keep(r, owned, touch));
	}
	if (owned.length > 0) { r.spanHandlers.set(handle, owned); }
	uiSetSpans(r.key, handle, texts, styles, presses, touches);
}

function measured(m: number[]): Result<MeasureRect, MeasureError> {
	if (m[0] >= 0) { return Result.err(MEASURE_ERRORS[m[0] as int32]); }
	return Result.ok({ x: m[1], y: m[2], width: m[3], height: m[4] });
}

function bridgeHost(r: GuestRoot): Host {
	const key = r.key;
	const capabilities = uiCapabilities(key);
	return {
		createElement: (tag: string): HostNode => remote(r, uiCreateElement(key, tag)) as HostNode,
		createText: (s: string): HostNode => remote(r, uiCreateText(key, s)) as HostNode,
		setText: (node: HostNode, s: string): void => { uiSetText(key, handleOf(node), s); },
		setAttr: (node: HostNode, name: string, value: string): void => { uiSetAttr(key, handleOf(node), name, value); },
		removeAttr: (node: HostNode, name: string): void => { uiRemoveAttr(key, handleOf(node), name); },
		setStyle: (node: HostNode, style: Style): void => { uiSetStyle(key, handleOf(node), style); },
		setStyleProp: null,
		setStyleClass: null,
		addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {
			addHandler(r, node, name, handler);
		},
		append: (parent: HostNode, child: HostNode): void => { uiAppend(key, handleOf(parent), handleOf(child)); },
		insertBefore: (parent: HostNode, node: HostNode, before: HostNode | null): void => {
			uiInsertBefore(key, handleOf(parent), handleOf(node), handleOf(before));
		},
		removeChild: (parent: HostNode, node: HostNode): void => {
			dropFreed(r, uiRemoveChild(key, handleOf(parent), handleOf(node)));
		},
		parentOf: (node: HostNode): HostNode | null => remote(r, uiParentOf(key, handleOf(node))),
		release: (node: HostNode): void => { dropFreed(r, uiRelease(key, handleOf(node))); },
		nextSibling: (node: HostNode): HostNode | null => remote(r, uiNextSibling(key, handleOf(node))),
		firstChild: (node: HostNode): HostNode | null => remote(r, uiFirstChild(key, handleOf(node))),
		cloneNode: null,
		voidArea: null,
		scrollTo: can(capabilities, CAN_SCROLL_TO) ? (node: HostNode, x: number, y: number, animated: boolean): void => {
			uiScrollTo(key, handleOf(node), x, y, animated);
		} : null,
		measureText: can(capabilities, CAN_MEASURE_TEXT) ? (text: string, style: Style): TextMeasure => {
			const m = uiMeasureText(key, text, style);
			return { width: m[0], height: m[1], ascender: m[2], descender: m[3] };
		} : null,
		focus: can(capabilities, CAN_FOCUS) ? (node: HostNode, focused: boolean): void => {
			uiFocus(key, handleOf(node), focused);
		} : null,
		measureInWindow: can(capabilities, CAN_MEASURE_IN_WINDOW) ? (node: HostNode): Result<MeasureRect, MeasureError> =>
			measured(uiMeasure(key, handleOf(node), NO_NODE)) : null,
		measureLayout: can(capabilities, CAN_MEASURE_LAYOUT) ? (node: HostNode, ancestor: HostNode): Result<MeasureRect, MeasureError> =>
			measured(uiMeasure(key, handleOf(node), handleOf(ancestor))) : null,
		paragraph: can(capabilities, CAN_PARAGRAPH) ? (host: Host, node: HostNode, before: HostNode | null, kids: NeonNode | null, spans: Accessor<TextSpan[]> | null): void => {
			spanParagraph((target: HostNode, delivered: TextSpan[]): void => { deliver(r, target, delivered); }, node, kids, spans);
		} : null,
	};
}

export function mountGuest(key: int32, view: () => NeonNode): void {
	if (roots.has(key)) { throw new Error(`guest root ${key} is already mounted`); }
	const r = new GuestRoot(key);
	const host = bridgeHost(r);
	roots.set(key, r);
	try {
		r.dispose = createRoot((dispose: Dispose): Dispose => {
			try {
				view()(host, remote(r, REGION) as HostNode, remote(r, REGION_END));
				return dispose;
			} catch (error) {
				dispose();
				throw error;
			}
		});
		flush();
	} catch (error) {
		raiserDispose(key);
		throw error;
	}
}

export function raiserDispatch(key: int32, handler: int32, name: string, e: NeonEvent): boolean {
	const r = rootAt(key);
	const run = handler >= 0 && handler < r.handlers.length ? r.handlers[handler] : null;
	if (run === null) { throw new Error(`guest root ${key} holds no handler ${handler} for ${name}`); }
	run(name, e);
	flush();
	return e.propagationStopped;
}

export function raiserDispose(key: int32): void {
	const r = rootAt(key);
	roots.delete(key);
	const dispose = r.dispose;
	r.dispose = null;
	if (dispose !== null) { dispose(); }
}
