import { NeonEvent, eventType, neonEvent } from "../../render/event";
import { Style } from "../../render/style";
import { FlexStyle, FlexDirection, Justify, Align, PositionType, Wrap, Display, Overflow } from "../../../../yoga/src/index";
import { asFlexStyleBody } from "../../macros/style/fields";

export enum NativeElementKind {
	View,
	Text,
	Scroll,
	Input,
	Switch,
	Indicator,
	Image,
	Modal,
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
	control: (tag: int32, phase: int32, value: string, width: number, height: number) => boolean;
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
	if (tag === "textinput" || tag === "multilinetextinput") { return NativeElementKind.Input; }
	if (tag === "switch") { return NativeElementKind.Switch; }
	if (tag === "activityindicator") { return NativeElementKind.Indicator; }
	if (tag === "image") { return NativeElementKind.Image; }
	if (tag === "modal") { return NativeElementKind.Modal; }
	return NativeElementKind.View;
}

export function nativeFlexStyle(style: Style, kind: NativeElementKind): FlexStyle {
	const flex = asFlexStyle(style);
	if (kind !== NativeElementKind.Text && flex.flexDirection === null) { flex.flexDirection = "column"; }
	if (kind === NativeElementKind.Scroll) { flex.overflow = "scroll"; }
	return flex;
}

export struct NativeTransform {
	scaleX: float32;
	scaleY: float32;
	translateX: float32;
	translateY: float32;
}

struct TransformCursor {
	css: string;
	at: int32;
}

function transformSpace(code: int32): boolean {
	return code === 32 || code === 9 || code === 10 || code === 12 || code === 13;
}

function skipTransformSpace(ref p: TransformCursor): void {
	while (p.at < p.css.length && transformSpace(p.css.charCodeAt(p.at))) { p.at += 1; }
}

function transformWord(ref p: TransformCursor, word: string): boolean {
	if (p.at + word.length > p.css.length) { return false; }
	for (let i = 0; i < word.length; i += 1) {
		if (p.css.charCodeAt(p.at + i) !== word.charCodeAt(i)) { return false; }
	}
	p.at += word.length as int32;
	return true;
}

function invalidTransform(p: TransformCursor): void {
	throw `native host: malformed or unsupported transform "${p.css}" at ${p.at}`;
}

function transformDigit(code: int32): boolean {
	return code >= 48 && code <= 57;
}

function transformNumber(ref p: TransformCursor, length: boolean): float64 {
	skipTransformSpace(p);
	let sign: float64 = 1;
	if (transformWord(p, "-")) { sign = -1; }
	else { transformWord(p, "+"); }
	let value: float64 = 0;
	let digits: int32 = 0;
	while (p.at < p.css.length && transformDigit(p.css.charCodeAt(p.at))) {
		value = value * 10 + (p.css.charCodeAt(p.at) - 48) as float64;
		p.at += 1;
		digits += 1;
	}
	if (transformWord(p, ".")) {
		const start = p.at;
		let place: float64 = 0.1;
		while (p.at < p.css.length && transformDigit(p.css.charCodeAt(p.at))) {
			value += ((p.css.charCodeAt(p.at) - 48) as float64) * place;
			place *= 0.1;
			p.at += 1;
			digits += 1;
		}
		if (start === p.at) { invalidTransform(p); }
	}
	if (digits === 0) { invalidTransform(p); }
	if (transformWord(p, "e") || transformWord(p, "E")) {
		let negative = false;
		if (transformWord(p, "-")) { negative = true; }
		else { transformWord(p, "+"); }
		const start = p.at;
		let exponent: int32 = 0;
		while (p.at < p.css.length && transformDigit(p.css.charCodeAt(p.at))) {
			exponent = exponent * 10 + p.css.charCodeAt(p.at) - 48;
			p.at += 1;
			if (exponent > 400) { invalidTransform(p); }
		}
		if (start === p.at) { invalidTransform(p); }
		for (let i = 0; i < exponent; i += 1) { value *= negative ? 0.1 : 10.0; }
	}
	value *= sign;
	if (length && !transformWord(p, "px") && value !== 0) { invalidTransform(p); }
	return value;
}

function finiteTransformNumber(value: float64): boolean {
	return value >= -3.4028234663852886e38 && value <= 3.4028234663852886e38;
}

export function nativeTransform(css: string | null): NativeTransform {
	if (css === null) { return { scaleX: 1, scaleY: 1, translateX: 0, translateY: 0 }; }
	let p: TransformCursor = { css: css as string, at: 0 };
	skipTransformSpace(p);
	if (transformWord(p, "none")) {
		skipTransformSpace(p);
		if (p.at !== p.css.length) { invalidTransform(p); }
		return { scaleX: 1, scaleY: 1, translateX: 0, translateY: 0 };
	}
	if (p.at === p.css.length) { invalidTransform(p); }
	let sx: float64 = 1;
	let sy: float64 = 1;
	let tx: float64 = 0;
	let ty: float64 = 0;
	while (p.at < p.css.length) {
		let scale = false;
		let axis: int32 = 0;
		if (transformWord(p, "scaleX")) { scale = true; axis = 1; }
		else if (transformWord(p, "scaleY")) { scale = true; axis = 2; }
		else if (transformWord(p, "scale")) { scale = true; }
		else if (transformWord(p, "translateX")) { axis = 1; }
		else if (transformWord(p, "translateY")) { axis = 2; }
		else if (!transformWord(p, "translate")) { invalidTransform(p); }
		if (!transformWord(p, "(")) { invalidTransform(p); }
		const first = transformNumber(p, !scale);
		const beforeSpace = p.at;
		skipTransformSpace(p);
		let second: float64 = scale ? first : 0;
		if (axis === 0 && p.at < p.css.length && p.css.charCodeAt(p.at) !== 41) {
			const comma = transformWord(p, ",");
			if (!comma && p.at === beforeSpace) { invalidTransform(p); }
			second = transformNumber(p, !scale);
			skipTransformSpace(p);
		}
		if (!transformWord(p, ")")) { invalidTransform(p); }
		if (scale) {
			sx *= axis === 2 ? 1 : first;
			sy *= axis === 1 ? 1 : (axis === 2 ? first : second);
		} else {
			tx += sx * (axis === 2 ? 0 : first);
			ty += sy * (axis === 1 ? 0 : (axis === 2 ? first : second));
		}
		if (!finiteTransformNumber(sx) || !finiteTransformNumber(sy) || !finiteTransformNumber(tx) || !finiteTransformNumber(ty)) { invalidTransform(p); }
		skipTransformSpace(p);
	}
	return {
		scaleX: sx as float32, scaleY: sy as float32,
		translateX: tx as float32, translateY: ty as float32,
	};
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
		const timeStamp = performance.now();
		let fired = false;
		for (const route of byTag.get(tag) as NativeEventRoute[]) {
			if (eventType(route.name) !== type) { continue; }
			const event = neonEvent(type);
			event.timeStamp = timeStamp;
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

	function control(tag: int32, phase: int32, value: string, width: number, height: number): boolean {
		if (!byTag.has(tag)) { return false; }
		const type = match (phase) {
			0 => "changetext",
			1 => "focus",
			2 => "blur",
			3 => "submitediting",
			4 => "valuechange",
			5 => "load",
			6 => "error",
			7 => "requestclose",
			_ => "",
		};
		if (type === "") { throw `native host: control phase ${phase} has no event`; }
		const timeStamp = performance.now();
		let fired = false;
		for (const route of byTag.get(tag) as NativeEventRoute[]) {
			if (eventType(route.name) !== type) { continue; }
			const event = neonEvent(type);
			event.timeStamp = timeStamp;
			event.value = value;
			event.width = width;
			event.height = height;
			route.handler(event);
			fired = true;
		}
		return fired;
	}

	return { add, remove, dispatch, scroll, scrollPhase, layout, control };
}
