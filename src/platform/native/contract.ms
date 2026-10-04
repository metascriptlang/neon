import { NeonEvent, eventType, neonEvent } from "../../render/event";
import { Style } from "../../render/style";
import { FlexStyle, FlexDirection, Justify, Align, PositionType, Wrap, Display, Overflow } from "../../../../yoga/src/index";
import { asFlexStyleBody } from "../../macros/style/fields";

export enum NativeElementKind {
	View,
	Text,
	Scroll,
}

interface NativeEventRoute {
	name: string;
	handler: (e: NeonEvent) => void;
}

export interface NativeEventRegistry {
	add: (tag: int32, name: string, handler: (e: NeonEvent) => void) => void;
	remove: (tag: int32) => void;
	dispatch: (tag: int32, phase: int32, x: number, y: number) => boolean;
	scroll: (tag: int32, x: number, y: number, width: number, height: number, contentWidth: number, contentHeight: number) => boolean;
	scrollPhase: (tag: int32, phase: int32, x: number, y: number, width: number, height: number, contentWidth: number, contentHeight: number) => boolean;
	layout: (tag: int32, x: number, y: number, width: number, height: number) => boolean;
}

function num(v: number | null): float32 | null {
	if (v === null) { return null; }
	return (v as number) as float32;
}

function dim(v: number | string | null, field: string): float32 | null {
	if (v === null) { return null; }
	if (typeof v === "string") { throw `native host: ${field} "${v as string}" is not supported, yoga takes points only`; }
	return (v as number) as float32;
}

asFlexStyleBody(0);

export function nativeElementKind(tag: string): NativeElementKind {
	if (tag === "text") { return NativeElementKind.Text; }
	if (tag === "scrollview") { return NativeElementKind.Scroll; }
	return NativeElementKind.View;
}

export function nativeFlexStyle(style: Style, kind: NativeElementKind): FlexStyle {
	const flex = asFlexStyle(style);
	if (kind !== NativeElementKind.Text && flex.flexDirection === null) { flex.flexDirection = "column"; }
	if (kind === NativeElementKind.Scroll) { flex.overflow = "scroll"; }
	return flex;
}

function fireRoutes(routes: NativeEventRoute[], type: string, x: number, y: number): boolean {
	let fired = false;
	for (const route of routes) {
		if (eventType(route.name) !== type) { continue; }
		const event = neonEvent(type);
		event.x = x;
		event.y = y;
		route.handler(event);
		fired = true;
	}
	return fired;
}

export function createNativeEventRegistry(): NativeEventRegistry {
	const byTag = new Map<int32, NativeEventRoute[]>();

	function add(tag: int32, name: string, handler: (e: NeonEvent) => void): void {
		let routes: NativeEventRoute[];
		if (byTag.has(tag)) {
			routes = byTag.get(tag) as NativeEventRoute[];
		} else {
			routes = [];
			byTag.set(tag, routes);
		}
		routes.push({ name, handler });
	}
	function remove(tag: int32): void {
		byTag.delete(tag);
	}

	function dispatch(tag: int32, phase: int32, x: number, y: number): boolean {
		if (!byTag.has(tag)) { return false; }
		const routes = byTag.get(tag) as NativeEventRoute[];
		if (phase === 0) { return fireRoutes(routes, "pointerdown", x, y); }
		if (phase === 1) { return fireRoutes(routes, "pointerup", x, y); }
		if (phase === 2) { return fireRoutes(routes, "press", x, y); }
		if (phase === 3) {
			const cancelled = fireRoutes(routes, "pointercancel", x, y);
			return fireRoutes(routes, "pointerleave", x, y) || cancelled;
		}
		return false;
	}


	function scrollPhase(tag: int32, phase: int32, x: number, y: number, width: number, height: number, contentWidth: number, contentHeight: number): boolean {
		if (!byTag.has(tag)) { return false; }
		const type = match (phase) {
			0 => "scroll",
			1 => "scrollbegindrag",
			2 => "scrollenddrag",
			3 => "momentumscrollbegin",
			4 => "momentumscrollend",
			5 => "refresh",
			_ => "",
		};
		let fired = false;
		for (const route of byTag.get(tag) as NativeEventRoute[]) {
			if (eventType(route.name) !== type) { continue; }
			const event = neonEvent(type);
			event.x = x;
			event.y = y;
			event.width = width;
			event.height = height;
			event.contentWidth = contentWidth;
			event.contentHeight = contentHeight;
			route.handler(event);
			fired = true;
		}
		return fired;
	}
	function scroll(tag: int32, x: number, y: number, width: number, height: number, contentWidth: number, contentHeight: number): boolean {
		return scrollPhase(tag, 0, x, y, width, height, contentWidth, contentHeight);
	}

	function layout(tag: int32, x: number, y: number, width: number, height: number): boolean {
		if (!byTag.has(tag)) { return false; }
		let fired = false;
		for (const route of byTag.get(tag) as NativeEventRoute[]) {
			if (eventType(route.name) !== "layout") { continue; }
			const event = neonEvent("layout");
			event.x = x;
			event.y = y;
			event.width = width;
			event.height = height;
			route.handler(event);
			fired = true;
		}
		return fired;
	}

	return { add, remove, dispatch, scroll, scrollPhase, layout };
}
