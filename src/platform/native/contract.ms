import { NeonEvent, eventType, neonEvent } from "../../render/event";
import { Style, PositionType as StylePositionType, Display as StyleDisplay, Overflow as StyleOverflow } from "../../render/style";
import { FlexStyle, PositionType, Display, Overflow } from "../../../../yoga/src/index";
import { asFlexStyleBody } from "../../macros/style/fields";

export enum NativeElementKind {
	View,
	Text,
	Scroll,
	Input,
	Image,
	Component,
}

interface NativeEventRoute {
	name: string;
	handler: (e: NeonEvent) => void;
	lifecycle?: ((e: NeonEvent) => void) | null;
}

export interface NativeEventDelivery {
	handler: (e: NeonEvent) => void;
	event: NeonEvent;
}

export interface NativeEventPacket {
	lifecycle: NativeEventDelivery[];
	listeners: NativeEventDelivery[];
}

export interface NativeEventRegistry {
	add: (tag: int32, name: string, handler: (e: NeonEvent) => void) => void;
	remove: (tag: int32) => void;
	addPhases: (tag: int32, name: string, lifecycle: (e: NeonEvent) => void,
		listener: (e: NeonEvent) => void) => void;
	capture: (tag: int32, phase: int32, x: number, y: number, timeStamp: number,
		touchOnly: boolean) => NativeEventPacket;
	dispatch: (tag: int32, phase: int32, x: number, y: number, timeStamp: number) => boolean;
	touch: (tag: int32, phase: int32, x: number, y: number, timeStamp: number) => boolean;
	scroll: (tag: int32, x: number, y: number, width: number, height: number, contentWidth: number, contentHeight: number) => boolean;
	scrollPhase: (tag: int32, phase: int32, x: number, y: number, width: number, height: number, contentWidth: number, contentHeight: number) => boolean;
	layout: (tag: int32, x: number, y: number, width: number, height: number) => boolean;
	control: (tag: int32, phase: int32, value: string, width: number, height: number) => boolean;
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

function position(v: StylePositionType | null): PositionType | null {
	if (v === null || v === "fixed" || v === "sticky") { return null; }
	return v;
}

function display(v: StyleDisplay | null): Display | null {
	if (v === "flex") { return "flex"; }
	if (v === "none") { return "none"; }
	if (v === "contents") { return "contents"; }
	return null;
}

function overflow(v: StyleOverflow | null): Overflow | null {
	if (v === "visible") { return "visible"; }
	if (v === "hidden" || v === "clip") { return "hidden"; }
	if (v === "scroll") { return "scroll"; }
	return null;
}

asFlexStyleBody(0);

export function nativeComponentOf(tag: string): string {
	return match (tag) {
		"switch" => "Switch from src/components/switch",
		"activityindicator" => "ActivityIndicator from src/components/activityIndicator",
		"modal" => "Modal from src/components/modal",
		"inputaccessoryview" => "InputAccessoryView from src/components/inputAccessoryView",
		"webview" => "WebView from src/components/webView",
		"video" => "Video from src/components/video",
		"camera" => "CameraView from src/components/cameraView",
		"svg" => "Svg from src/components/svg/elements",
		_ => "",
	};
}

export function nativeElementKind(tag: string): NativeElementKind {
	if (tag === "text") { return NativeElementKind.Text; }
	if (tag === "scrollview") { return NativeElementKind.Scroll; }
	if (tag === "textinput" || tag === "multilinetextinput") { return NativeElementKind.Input; }
	if (tag === "image") { return NativeElementKind.Image; }
	if (nativeComponentOf(tag) !== "") { return NativeElementKind.Component; }
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
	rotate: float32;
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
		value = value * 10 + ((p.css.charCodeAt(p.at) - 48) as float64);
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
	if (css === null) { return { scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotate: 0 }; }
	let p: TransformCursor = { css: css as string, at: 0 };
	skipTransformSpace(p);
	if (transformWord(p, "none")) {
		skipTransformSpace(p);
		if (p.at !== p.css.length) { invalidTransform(p); }
		return { scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotate: 0 };
	}
	if (p.at === p.css.length) { invalidTransform(p); }
	let sx: float64 = 1;
	let sy: float64 = 1;
	let tx: float64 = 0;
	let ty: float64 = 0;
	let angle: float64 = 0;
	while (p.at < p.css.length) {
		if (transformWord(p, "rotateZ") || transformWord(p, "rotate")) {
			if (!transformWord(p, "(")) { invalidTransform(p); }
			angle += transformAngle(p);
			skipTransformSpace(p);
			if (!transformWord(p, ")")) { invalidTransform(p); }
			skipTransformSpace(p);
			continue;
		}
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
			const lx = sx * (axis === 2 ? 0 : first);
			const ly = sy * (axis === 1 ? 0 : (axis === 2 ? first : second));
			const radians = angle * Math.PI / 180;
			tx += Math.cos(radians) * lx - Math.sin(radians) * ly;
			ty += Math.sin(radians) * lx + Math.cos(radians) * ly;
		}
		if (!finiteTransformNumber(sx) || !finiteTransformNumber(sy) || !finiteTransformNumber(tx) || !finiteTransformNumber(ty)) { invalidTransform(p); }
		skipTransformSpace(p);
	}
	return {
		scaleX: sx as float32, scaleY: sy as float32,
		translateX: tx as float32, translateY: ty as float32,
		rotate: angle as float32,
	};
}

function transformAngle(ref p: TransformCursor): float64 {
	const value = transformNumber(p, false);
	if (transformWord(p, "deg")) { return value; }
	if (transformWord(p, "rad")) { return value * 180 / Math.PI; }
	if (transformWord(p, "turn")) { return value * 360; }
	if (transformWord(p, "grad")) { return value * 0.9; }
	if (value !== 0) { invalidTransform(p); }
	return 0;
}

function fireRoute(route: NativeEventRoute, event: NeonEvent): void {
	const lifecycle = route.lifecycle;
	if (lifecycle !== null) { lifecycle(event); }
	route.handler(event);
}

function fireRoutes(routes: NativeEventRoute[], type: string, x: number, y: number, timeStamp: number): boolean {
	let fired = false;
	for (const route of routes) {
		if (eventType(route.name) !== type) { continue; }
		const event = neonEvent(type);
		event.pointerOrigin = true;
		event.x = x;
		event.y = y;
		event.timeStamp = timeStamp;
		fireRoute(route, event);
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

	function addPhases(tag: int32, name: string, lifecycle: (e: NeonEvent) => void,
		listener: (e: NeonEvent) => void): void {
		add(tag, name, listener);
		const routes = byTag.get(tag) as NativeEventRoute[];
		routes[routes.length - 1].lifecycle = lifecycle;
	}

	function capture(tag: int32, phase: int32, x: number, y: number, timeStamp: number,
		touchOnly: boolean): NativeEventPacket {
		const packet: NativeEventPacket = { lifecycle: [], listeners: [] };
		if (!byTag.has(tag)) { return packet; }
		const types: string[] = touchOnly
			? match (phase) { 0 => ["touchstart"], 1 => ["touchend"], 3 => ["touchcancel"],
				4 => ["touchmove"], _ => [] }
			: match (phase) { 0 => ["pointerdown"], 1 => ["pointerup"], 2 => ["press"],
				3 => ["pointercancel", "pointerleave"], 4 => ["pointermove"], _ => [] };
		for (const type of types) {
			for (const route of byTag.get(tag) as NativeEventRoute[]) {
				if (eventType(route.name) !== type) { continue; }
				const event = neonEvent(type);
				event.pointerOrigin = true;
				event.x = x; event.y = y; event.timeStamp = timeStamp;
				const lifecycle = route.lifecycle;
				if (lifecycle !== null) {
					packet.lifecycle.push({ handler: lifecycle, event: { ...event } });
				}
				packet.listeners.push({ handler: route.handler, event });
			}
		}
		return packet;
	}

	function dispatch(tag: int32, phase: int32, x: number, y: number, timeStamp: number): boolean {
		if (!byTag.has(tag)) { return false; }
		const routes = byTag.get(tag) as NativeEventRoute[];
		if (phase === 0) { return fireRoutes(routes, "pointerdown", x, y, timeStamp); }
		if (phase === 1) { return fireRoutes(routes, "pointerup", x, y, timeStamp); }
		if (phase === 2) { return fireRoutes(routes, "press", x, y, timeStamp); }
		if (phase === 3) {
			const cancelled = fireRoutes(routes, "pointercancel", x, y, timeStamp);
			return fireRoutes(routes, "pointerleave", x, y, timeStamp) || cancelled;
		}
		if (phase === 4) { return fireRoutes(routes, "pointermove", x, y, timeStamp); }
		return false;
	}

	function touch(tag: int32, phase: int32, x: number, y: number, timeStamp: number): boolean {
		if (!byTag.has(tag)) { return false; }
		const type = match (phase) {
			0 => "touchstart",
			1 => "touchend",
			3 => "touchcancel",
			4 => "touchmove",
			_ => "",
		};
		if (type === "") { return false; }
		return fireRoutes(byTag.get(tag) as NativeEventRoute[], type, x, y, timeStamp);
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
			fireRoute(route, event);
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
			fireRoute(route, event);
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
			9 => "selectionchange",
			10 => "loadstart",
			11 => "message",
			12 => "shouldstartload",
			13 => "progress",
			14 => "end",
			15 => "accessibilityaction",
			16 => "keypress",
			30 => "cameraready",
			31 => "mounterror",
			32 => "picture",
			_ => "",
		};
		if (type === "") { throw `native host: control phase ${phase} has no event`; }
		const timeStamp = performance.now();
		let fired = false;
		for (const route of byTag.get(tag) as NativeEventRoute[]) {
			if (eventType(route.name) !== type) { continue; }
			const event = neonEvent(type);
			event.timeStamp = timeStamp;
			if (type === "keypress") { event.key = value; } else { event.value = value; }
			event.width = width;
			event.height = height;
			fireRoute(route, event);
			fired = true;
		}
		return fired;
	}

	return { add, addPhases, capture, remove, dispatch, touch, scroll, scrollPhase, layout, control };
}
