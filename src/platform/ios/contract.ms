import { NeonEvent, eventType, neonEvent } from "../../render/event";
import { Style } from "../../render/style";
import { FlexStyle, FlexDirection, Justify, Align, PositionType, Wrap, Display, Overflow } from "../../../../yoga/src/index";
import { asFlexStyleBody } from "../../macros/style/fields";

export enum IosElementKind {
	View,
	Text,
}

interface IosEventRoute {
	name: string;
	handler: (e: NeonEvent) => void;
}

export interface IosEventRegistry {
	add: (tag: int32, name: string, handler: (e: NeonEvent) => void) => void;
	remove: (tag: int32) => void;
	dispatch: (tag: int32, phase: int32, x: number, y: number) => boolean;
}

function num(v: number | null): float32 | null {
	if (v === null) { return null; }
	return (v as number) as float32;
}

function dim(v: number | string | null): float32 | string | null {
	if (v === null) { return null; }
	if (typeof v === "string") { return v as string; }
	return (v as number) as float32;
}

asFlexStyleBody(0);

export function iosElementKind(tag: string): IosElementKind {
	return tag === "text" ? IosElementKind.Text : IosElementKind.View;
}

export function iosFlexStyle(style: Style, isText: boolean): FlexStyle {
	const flex = asFlexStyle(style);
	if (!isText && flex.flexDirection === null) { flex.flexDirection = "column"; }
	return flex;
}

function fireRoutes(routes: IosEventRoute[], type: string, x: number, y: number): boolean {
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

export function createIosEventRegistry(): IosEventRegistry {
	const byTag = new Map<int32, IosEventRoute[]>();

	function add(tag: int32, name: string, handler: (e: NeonEvent) => void): void {
		let routes: IosEventRoute[];
		if (byTag.has(tag)) {
			routes = byTag.get(tag) as IosEventRoute[];
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
		const routes = byTag.get(tag) as IosEventRoute[];
		if (phase === 0) { return fireRoutes(routes, "pointerdown", x, y); }
		if (phase === 1) { return fireRoutes(routes, "pointerup", x, y); }
		if (phase === 2) { return fireRoutes(routes, "press", x, y); }
		if (phase === 3) {
			const cancelled = fireRoutes(routes, "pointercancel", x, y);
			return fireRoutes(routes, "pointerleave", x, y) || cancelled;
		}
		return false;
	}

	return { add, remove, dispatch };
}
