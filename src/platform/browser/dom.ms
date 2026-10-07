// Browser DOM host — JS backend only. Same render(node, host, parent)
// drives this; here the host ops map to real document.* / Node APIs.

import { Host, HostNode } from "../../render/host";
import { Style, StyleValue } from "../../render/style";
import { registerCss, collectCss, onCssChange } from "../../render/sheet";
import { NeonEvent, neonEvent, eventType } from "../../render/event";
import { onCleanup } from "../../core/cleanup";
import { htmlTagFor } from "../../render/node";
import { publishWindow, publishColorScheme } from "../../render/environment";
import { CssStyle, applyCss, applyCssProp } from "./domCss";
import { VisibleContentPosition, parseVisibleContent } from "../../render/visibleContent";
import { installBrowserAppServices } from "./appServices";

extern class ClassList {
	extern add(name: cstring): void;
	extern remove(name: cstring): void;
	extern toggle(name: cstring): void;
	extern contains(name: cstring): boolean;
}

extern class DomRect {
	left: number;
	top: number;
	width: number;
	height: number;
}

extern class Reflect {
	static extern has(target: Node, key: cstring): boolean;
}

extern class ResizeObserver {
	extern observe(target: Node): void;
	extern disconnect(): void;
}

interface DomScrollOptions {
	left: number;
	top: number;
	behavior: string;
}

extern class Node {
	textContent: cstring;
	scrollLeft: number;
	scrollTop: number;
	scrollWidth: number;
	scrollHeight: number;
	offsetWidth: number;
	offsetHeight: number;
	offsetLeft: number;
	offsetTop: number;
	offsetParent: Node | null;
	parentNode: Node | null;
	isConnected: boolean;
	nodeType: number;
	tagName: string;
	extern blur(): void;
	extern focus(): void;
	extern contains(node: Node): boolean;
	extern scroll(options: DomScrollOptions): void;
	extern getBoundingClientRect(): DomRect;
	style: CssStyle;
	classList: ClassList;
	nextSibling: Node;
	firstChild: Node;
	extern cloneNode(deep: boolean): Node;
	extern appendChild(child: Node): void;
	extern insertBefore(node: Node, ref: Node | null): void;
	extern moveBefore(node: Node, ref: Node | null): void;
	isConnected: boolean;
	extern removeChild(child: Node): void;
	value: cstring;
	checked: boolean;
	naturalWidth: number;
	naturalHeight: number;
	extern setAttribute(name: cstring, value: cstring): void;
	extern removeAttribute(name: cstring): void;
	extern addEventListener(name: cstring, handler: (e: DomEvent) => void, capture: boolean): void;
	extern removeEventListener(name: cstring, handler: (e: DomEvent) => void, capture: boolean): void;
}

extern class DomTouch {
	clientX: number;
	clientY: number;
}

extern class DomTouchList {
	length: number;
	extern item(index: number): DomTouch;
}

extern class CSSStyleDeclaration {
	overflowX: string;
	overflowY: string;
	scrollbarWidth: string;
	touchAction: string;
	overscrollBehaviorY: string;
	overflowAnchor: string;
	position: string;
}

// Only the fields Neon projects onto NeonEvent. Each is read ONLY for the event
// types that always carry it (`value` on input/change, `key` on the key events,
// clientX/Y on the mouse ones) — a DOM event object simply lacks the others, and
// there is no way to probe for absence across the extern boundary.
extern class DomEvent {
	target: Node;
	timeStamp: number;
	clientX: number;
	clientY: number;
	key: string;
	code: string;
	altKey: boolean;
	ctrlKey: boolean;
	metaKey: boolean;
	shiftKey: boolean;
	repeat: boolean;
	isComposing: boolean;
	touches: DomTouchList;
	defaultPrevented: boolean;
	extern preventDefault(): void;
	extern stopPropagation(): void;
}

extern class MediaQueryList {
	matches: boolean;
	extern addEventListener(name: cstring, handler: (e: DomEvent) => void): void;
}

extern class window {
	static innerWidth: number;
	static innerHeight: number;
	static extern addEventListener(name: cstring, handler: (e: DomEvent) => void): void;
	static extern matchMedia(query: cstring): MediaQueryList;
}

let environmentWatched = false;

function watchEnvironment(): void {
	if (environmentWatched) { return; }
	environmentWatched = true;
	const scheme = window.matchMedia("(prefers-color-scheme: dark)");
	const publish = (): void => {
		publishWindow(window.innerWidth, window.innerHeight);
		publishColorScheme(scheme.matches ? "dark" : "light");
	};
	publish();
	window.addEventListener("resize", (e: DomEvent): void => { publish(); });
	scheme.addEventListener("change", (e: DomEvent): void => { publish(); });
}

extern function requestAnimationFrame(callback: (time: number) => void): number;
extern function cancelAnimationFrame(id: number): void;
extern function queueMicrotask(callback: () => void): void;

const ELEMENT_NODE = 1;

function layoutStart(node: Node, horizontal: boolean): number {
	let start = 0.0;
	let at: Node | null = node;
	while (at !== null) {
		start += horizontal ? (at as Node).offsetLeft : (at as Node).offsetTop;
		at = (at as Node).offsetParent;
	}
	return start;
}

interface DomScrollRoute {
	type: string;
	handler: (e: NeonEvent) => void;
}

class DomScrollState {
	el: Node;
	horizontal: boolean = false;
	enabled: boolean = true;
	horizontalIndicator: boolean = true;
	verticalIndicator: boolean = true;
	paging: boolean = false;
	dismiss: string = "none";
	taps: string = "never";
	refreshEnabled: boolean = false;
	refreshing: boolean = false;
	refreshPending: boolean = false;
	touching: boolean = false;
	dragging: boolean = false;
	momentum: boolean = false;
	startX: number = 0;
	startY: number = 0;
	pull: number = 0;
	frame: number = -1;
	stableFrames: int32 = 0;
	lastX: number = -1;
	lastY: number = -1;
	indicator: Node | null = null;
	routes: DomScrollRoute[] = [];
	visibleContent: VisibleContentPosition | null = null;
	anchor: Node | null = null;
	anchorStart: number = 0;
	shifted: boolean = false;

	constructor(el: Node) { this.el = el; }

	content(): Node | null {
		let child = this.el.firstChild as Node | null;
		while (child !== null && (child as Node).nodeType !== ELEMENT_NODE) {
			child = (child as Node).nextSibling as Node | null;
		}
		return child;
	}

	// RN RCTScrollViewComponentView _prepareForMaintainVisibleScrollPosition, before a batch of
	// host writes instead of a mount transaction.
	prepareVisibleContent(): void {
		this.anchor = null;
		const position = this.visibleContent;
		const content = this.content();
		if (position === null || content === null || !this.el.isConnected) { return; }
		const offset = this.horizontal ? this.el.scrollLeft : this.el.scrollTop;
		const origin = layoutStart(content as Node, this.horizontal);
		let index: int32 = 0;
		let child = (content as Node).firstChild as Node | null;
		while (child !== null) {
			const node = child as Node;
			child = node.nextSibling as Node | null;
			if (node.nodeType !== ELEMENT_NODE) { continue; }
			index += 1;
			if (index <= (position as VisibleContentPosition).minIndexForVisible) { continue; }
			const start = layoutStart(node, this.horizontal) - origin;
			this.anchor = node;
			this.anchorStart = start;
			const length = this.horizontal ? node.offsetWidth : node.offsetHeight;
			if (start + length > offset) { break; }
		}
	}

	adjustVisibleContent(): void {
		const anchor = this.anchor;
		const position = this.visibleContent;
		const content = this.content();
		this.anchor = null;
		if (anchor === null || position === null || content === null) { return; }
		if ((anchor as Node).parentNode !== content) { return; }
		const origin = layoutStart(content as Node, this.horizontal);
		const delta = layoutStart(anchor as Node, this.horizontal) - origin - this.anchorStart;
		if (Math.abs(delta) <= 0.5) { return; }
		const before = this.horizontal ? this.el.scrollLeft : this.el.scrollTop;
		if (this.horizontal) {
			this.el.scrollLeft = before + delta;
		} else {
			this.el.scrollTop = before + delta;
		}
		this.shifted = (this.horizontal ? this.el.scrollLeft : this.el.scrollTop) !== before;
		const threshold = (position as VisibleContentPosition).autoscrollToTopThreshold;
		if (threshold !== null && before <= (threshold as number)) {
			this.el.scroll({
				left: this.horizontal ? 0 : this.el.scrollLeft,
				top: this.horizontal ? this.el.scrollTop : 0,
				behavior: "smooth",
			});
		}
	}

	fire(type: string): void {
		const e = neonEvent(type);
		e.timeStamp = performance.now();
		e.x = this.el.scrollLeft; e.y = this.el.scrollTop;
		e.width = this.el.offsetWidth; e.height = this.el.offsetHeight;
		e.contentWidth = this.el.scrollWidth; e.contentHeight = this.el.scrollHeight;
		for (const route of this.routes) { if (route.type === type) { route.handler(e); } }
	}

	beginDrag(): void {
		if (this.dragging || !this.enabled) { return; }
		if (this.momentum) { this.momentum = false; this.fire("momentumscrollend"); }
		this.dragging = true;
		if (this.dismiss === "on-drag") { blurInput(); }
		this.fire("scrollbegindrag");
	}

	beginMomentum(): void {
		if (this.momentum) { return; }
		this.momentum = true;
		this.stableFrames = 0;
		this.lastX = this.el.scrollLeft; this.lastY = this.el.scrollTop;
		this.fire("momentumscrollbegin");
		this.scheduleSettle();
	}

	scheduleSettle(): void {
		if (this.frame >= 0) { return; }
		this.frame = requestAnimationFrame((time: number): void => {
			this.frame = -1;
			if (!this.momentum) { return; }
			const x = this.el.scrollLeft;
			const y = this.el.scrollTop;
			if (x !== this.lastX || y !== this.lastY || this.touching) { this.stableFrames = 0; }
			else { this.stableFrames += 1; }
			this.lastX = x; this.lastY = y;
			if (this.stableFrames >= 3) { this.scrollEnd(); }
			if (this.momentum) { this.scheduleSettle(); }
		});
	}

	dispose(): void {
		if (this.frame >= 0) { cancelAnimationFrame(this.frame); }
		this.frame = -1;
		this.momentum = false;
		this.routes = [];
	}

	apply(): void {
		const css = this.el.style as unknown as CSSStyleDeclaration;
		css.overflowX = this.enabled && this.horizontal ? "auto" : "hidden";
		css.overflowY = this.enabled && !this.horizontal ? "auto" : "hidden";
		css.touchAction = this.enabled ? (this.horizontal ? "pan-x" : "pan-y") : "none";
		css.scrollbarWidth = !this.horizontalIndicator && !this.verticalIndicator ? "none" : "auto";
		if (this.horizontalIndicator) { this.el.classList.remove("neon-hide-horizontal"); }
		else { this.el.classList.add("neon-hide-horizontal"); }
		if (this.verticalIndicator) { this.el.classList.remove("neon-hide-vertical"); }
		else { this.el.classList.add("neon-hide-vertical"); }
		css.overscrollBehaviorY = this.refreshEnabled ? "contain" : "";
		css.overflowAnchor = this.visibleContent === null ? "" : "none";
		if (this.indicator !== null && (css.position === "" || css.position === "static")) { css.position = "relative"; }
	}

	showRefresh(): void {
		if (this.indicator === null) { return; }
		const indicator = this.indicator as Node;
		indicator.setAttribute("style", `position:absolute;top:8px;left:calc(50% - 14px);width:28px;height:28px;border-radius:50%;background:white;color:black;text-align:center;line-height:28px;pointer-events:none;display:${this.refreshing || this.refreshPending || this.pull > 0 ? "block" : "none"}`);
		indicator.setAttribute("aria-busy", this.refreshing || this.refreshPending ? "true" : "false");
	}

	mountRefresh(): void {
		if (!this.refreshEnabled || this.indicator !== null) { return; }
		const indicator = document.createElement("div");
		indicator.textContent = "↻";
		indicator.classList.add("neon-refresh-indicator");
		indicator.setAttribute("role", "progressbar");
		indicator.setAttribute("aria-label", "Refreshing");
		this.indicator = indicator;
		(this.el.style as unknown as CSSStyleDeclaration).position = "relative";
		this.el.appendChild(indicator);
		this.showRefresh();
	}

	setOption(name: string, value: string): void {
		const yes = value === "true";
		const defaultYes = value === "" || yes;
		match (name) {
			"horizontal" => { this.horizontal = yes; },
			"scrollEnabled" => { this.enabled = defaultYes; },
			"showsHorizontalScrollIndicator" => { this.horizontalIndicator = defaultYes; },
			"showsVerticalScrollIndicator" => { this.verticalIndicator = defaultYes; },
			"pagingEnabled" => { this.paging = yes; },
			"keyboardDismissMode" => {
				if (value === "interactive") { throw "ScrollView: keyboardDismissMode interactive needs iOS's interactive keyboard; the browser supports none and on-drag"; }
				this.dismiss = value;
			},
			"keyboardShouldPersistTaps" => { this.taps = value === "" ? "never" : value; },
			"refreshEnabled" => { this.refreshEnabled = yes; },
			"refreshing" => { this.refreshing = yes; this.refreshPending = false; this.showRefresh(); },
			"maintainVisibleContentPosition" => {
				this.visibleContent = parseVisibleContent(value);
			},
			_ => {},
		}
		this.apply();
	}

	scrollEnd(): void {
		if (this.touching) { return; }
		if (this.paging) {
			const interval = this.horizontal ? this.el.offsetWidth : this.el.offsetHeight;
			const offset = this.horizontal ? this.el.scrollLeft : this.el.scrollTop;
			const length = this.horizontal ? this.el.scrollWidth : this.el.scrollHeight;
			if (interval > 0) {
				const target = Math.min(Math.max(0, length - interval), Math.round(offset / interval) * interval);
				if (Math.abs(target - offset) > 0.5) {
					this.beginMomentum();
					this.el.scroll({ left: this.horizontal ? target : 0, top: this.horizontal ? 0 : target, behavior: "smooth" });
					return;
				}
			}
		}
		if (this.momentum) { this.momentum = false; this.fire("momentumscrollend"); }
	}
}

function ariaRole(role: string): string | null {
	return match (role) {
		"header" => "heading",
		"image" => "img",
		"adjustable" => "slider",
		"summary" => "region",
		"none" => "presentation",
		"text" => null,
		_ => role,
	};
}

const CONTROL_CSS = ".neon-activity{box-sizing:border-box;border-radius:50%;border:3px solid currentColor;border-top-color:transparent;animation:neon-activity-spin 0.8s linear infinite;color:#999999}.neon-activity[data-animating=false]{animation:none}.neon-activity[data-animating=false]:not([data-hides=false]){visibility:hidden}@keyframes neon-activity-spin{to{transform:rotate(360deg)}}.neon-image{object-fit:cover}.neon-image[data-resize=contain]{object-fit:contain}.neon-image[data-resize=stretch]{object-fit:fill}.neon-image[data-resize=center]{object-fit:none}.neon-image:not([src]){visibility:hidden}";
const controlKinds = new Map<Node, string>();
const switchValues = new Map<Node, boolean>();

function writeControlAttr(el: Node, kind: string, name: string, value: string): boolean {
	if (kind === "switch") {
		if (name === "value") {
			el.checked = value === "true";
			switchValues.set(el, value === "true");
			return true;
		}
		if (name === "disabled") {
			if (value === "true") { el.setAttribute("disabled", ""); } else { el.removeAttribute("disabled"); }
			return true;
		}
		return name === "thumbColor" || name === "trackColorOn" || name === "trackColorOff";
	}
	if (kind === "activityindicator") {
		if (name === "animating") { el.setAttribute("data-animating", value); return true; }
		if (name === "hidesWhenStopped") { el.setAttribute("data-hides", value); return true; }
		if (name === "color") { el.style.color = value; return true; }
		return false;
	}
	if (kind === "image") {
		if (name === "source") { el.setAttribute("src", value); return true; }
		if (name === "resizeMode") { el.setAttribute("data-resize", value); return true; }
		if (name === "accessibilityLabel") { el.setAttribute("alt", value); }
		return false;
	}
	return false;
}

function writeDomAttr(el: Node, name: string, value: string): void {
	if (controlKinds.has(el) && writeControlAttr(el, controlKinds.get(el) as string, name, value)) { return; }
	if (name === "value") { el.value = value; return; }
	if (name === "defaultValue") {
		const current: string = el.value;
		if (current === "") { el.value = value; }
		return;
	}
	if (name === "accessibilityLabel") { el.setAttribute("aria-label", value); return; }
	if (name === "accessibilityHint") { el.setAttribute("aria-description", value); return; }
	if (name === "accessibilityRole") {
		const role = ariaRole(value);
		if (role === null) { el.removeAttribute("role"); } else { el.setAttribute("role", role as string); }
		return;
	}
	if (name === "accessible" || name === "blurOnSubmit" || name === "multiline" || name === "placeholderTextColor") { return; }
	if (name === "editable") {
		if (value === "false") { el.setAttribute("readonly", ""); } else { el.removeAttribute("readonly"); }
		return;
	}
	if (name === "secureTextEntry") {
		el.setAttribute("type", value === "true" ? "password" : "text");
		return;
	}
	if (name === "keyboardType") {
		const mode = match (value) {
			"numeric" | "number-pad" => "numeric",
			"decimal-pad" => "decimal",
			"phone-pad" => "tel",
			"email-address" => "email",
			"url" => "url",
			_ => "text",
		};
		el.setAttribute("inputmode", mode);
		return;
	}
	if (name === "returnKeyType") { el.setAttribute("enterkeyhint", value); return; }
	if (name === "autoCapitalize") { el.setAttribute("autocapitalize", value); return; }
	if (name === "autoCorrect") { el.setAttribute("autocorrect", value === "false" ? "off" : "on"); return; }
	if (name === "maxLength") { el.setAttribute("maxlength", value); return; }
	if (name === "autoFocus") {
		if (value === "true") { el.setAttribute("autofocus", ""); } else { el.removeAttribute("autofocus"); }
		return;
	}
	el.setAttribute(name, value);
}

function domAttrName(name: string): string {
	return match (name) {
		"accessibilityLabel" => "aria-label",
		"accessibilityHint" => "aria-description",
		"accessibilityRole" => "role",
		"editable" => "readonly",
		"keyboardType" => "inputmode",
		"returnKeyType" => "enterkeyhint",
		"autoCapitalize" => "autocapitalize",
		"autoCorrect" => "autocorrect",
		"maxLength" => "maxlength",
		"autoFocus" => "autofocus",
		"secureTextEntry" => "type",
		_ => name,
	};
}

function inputNode(node: Node): boolean { return node.tagName === "INPUT" || node.tagName === "TEXTAREA"; }
function blurInput(): void {
	const focused = document.activeElement;
	if (inputNode(focused)) { focused.blur(); }
}

extern class document {
	static body: Node;
	static head: Node;
	static activeElement: Node;
	static extern createElement(tag: cstring): Node;
	static extern createTextNode(s: cstring): Node;
}

// One <style> element owns every rule the program registered. Rewriting its
// whole text on each new rule is fine because registration happens as sheets
// are first mounted, not per element, and the browser reparses one small block.
let sheetNode: Node | null = null;

const SCROLL_CLASS = "neon-scrollview";

function flushSheet(): void {
	if (sheetNode === null) {
		const n = document.createElement("style");
		document.head.appendChild(n);
		sheetNode = n;
	}
	(sheetNode as Node).textContent = collectCss();
}

export function documentBody(): HostNode {
	return document.body as unknown as HostNode;
}

class DomLayoutState {
	node: Node;
	handler: (e: NeonEvent) => void;
	active: boolean = true;
	known: boolean = false;
	x: number = 0;
	y: number = 0;
	width: number = 0;
	height: number = 0;

	constructor(node: Node, handler: (e: NeonEvent) => void) {
		this.node = node;
		this.handler = handler;
	}
}

export function domHost(): Host {
	// The registry may already hold rules from module init — a theme's :root
	// among them — and from here on every change mounts itself, including a
	// swap that touches no node.
	onCssChange(flushSheet);
	flushSheet();
	watchEnvironment();
	installBrowserAppServices();
	let scrollRule = false;
	let controlRule = false;
	const scrolls = new Map<Node, DomScrollState>();
	const cleanups = new Map<Node, (() => void)[]>();
	const presses = new Map<Node, boolean>();
	const layouts: DomLayoutState[] = [];
	let layoutFrame: number = -1;
	const keepers: DomScrollState[] = [];
	let adjustQueued = false;
	function adjustVisibleContent(): void {
		adjustQueued = false;
		for (const state of keepers.slice(0, keepers.length)) { state.adjustVisibleContent(); }
	}
	function prepareVisibleContent(): void {
		if (keepers.length === 0 || adjustQueued) { return; }
		adjustQueued = true;
		for (const state of keepers) { state.prepareVisibleContent(); }
		queueMicrotask(adjustVisibleContent);
	}
	function trackKeeper(state: DomScrollState): void {
		const at = keepers.indexOf(state);
		if (at >= 0) { keepers.splice(at, 1); }
		if (state.visibleContent !== null && scrolls.has(state.el)) { keepers.push(state); }
	}
	function flushLayouts(): void {
		const count = layouts.length;
		for (let i = 0; i < count; i += 1) {
			const state = layouts[i];
			if (!state.active || state.node.parentNode === null) { continue; }
			let x = 0.0;
			let y = 0.0;
			let ancestor: Node | null = state.node;
			while (ancestor !== null) {
				x += (ancestor as Node).offsetLeft;
				y += (ancestor as Node).offsetTop;
				ancestor = (ancestor as Node).offsetParent;
			}
			ancestor = state.node.parentNode;
			while (ancestor !== null) {
				x -= (ancestor as Node).offsetLeft;
				y -= (ancestor as Node).offsetTop;
				ancestor = (ancestor as Node).offsetParent;
			}
			const width = state.node.offsetWidth;
			const height = state.node.offsetHeight;
			if (state.known && x === state.x && y === state.y && width === state.width && height === state.height) { continue; }
			state.known = true;
			state.x = x; state.y = y; state.width = width; state.height = height;
			const event = neonEvent("layout");
			event.x = x; event.y = y; event.width = width; event.height = height;
			state.handler(event);
		}
		let live = 0;
		for (const state of layouts) {
			if (state.active) { layouts[live] = state; live += 1; }
		}
		while (layouts.length > live) { layouts.pop(); }
	}
	function scheduleLayouts(): void {
		if (layoutFrame >= 0 || layouts.length === 0) { return; }
		layoutFrame = requestAnimationFrame((): void => {
			layoutFrame = -1;
			flushLayouts();
		});
	}
	function releaseOne(el: Node): void {
		controlKinds.delete(el);
		switchValues.delete(el);
		if (cleanups.has(el)) {
			for (const cleanup of cleanups.get(el) as (() => void)[]) { cleanup(); }
			cleanups.delete(el);
		}
		if (scrolls.has(el)) {
			const state = scrolls.get(el) as DomScrollState;
			scrolls.delete(el);
			trackKeeper(state);
		}
		presses.delete(el);
	}
	function release(el: Node): void {
		let child = el.firstChild as Node | null;
		while (child !== null) {
			const next = (child as Node).nextSibling as Node | null;
			release(child as Node);
			child = next;
		}
		releaseOne(el);
	}
	function keep(el: Node, cleanup: () => void): void {
		if (!cleanups.has(el)) {
			cleanups.set(el, []);
			onCleanup((): void => { releaseOne(el); });
		}
		(cleanups.get(el) as (() => void)[]).push(cleanup);
	}
	const listen = (el: Node, type: string, handler: (e: DomEvent) => void, capture: boolean): void => {
		let active = true;
		const guarded = (e: DomEvent): void => { if (active) { handler(e); } };
		el.addEventListener(type, guarded, capture);
		keep(el, (): void => { active = false; el.removeEventListener(type, guarded, capture); });
	};
	function installScroll(el: Node): void {
		const state = new DomScrollState(el);
		scrolls.set(el, state);
		keep(el, (): void => { state.dispose(); });
		state.apply();
		listen(el, "scroll", (e: DomEvent): void => {
			if (state.shifted && !state.touching) { state.shifted = false; }
			else if (state.touching) { state.beginDrag(); }
			else { state.beginMomentum(); }
			state.fire("scroll");
		}, false);
		listen(el, "scrollend", (e: DomEvent): void => { state.scrollEnd(); }, false);
		listen(el, "touchstart", (e: DomEvent): void => {
			if (!state.enabled || e.touches.length !== 1) { return; }
			state.touching = true;
			state.startX = e.touches.item(0).clientX;
			state.startY = e.touches.item(0).clientY;
			state.pull = 0;
		}, false);
		listen(el, "touchmove", (e: DomEvent): void => {
			if (!state.touching || !state.enabled || e.touches.length !== 1) { return; }
			const dx = e.touches.item(0).clientX - state.startX;
			const dy = e.touches.item(0).clientY - state.startY;
			if (Math.abs(state.horizontal ? dx : dy) > 5) { state.beginDrag(); }
			if (state.refreshEnabled && el.scrollTop <= 0 && dy > 0 && Math.abs(dy) > Math.abs(dx)) {
				state.pull = dy;
				state.showRefresh();
				e.preventDefault();
			}
		}, false);
		const endTouch = (e: DomEvent, cancelled: boolean): void => {
			if (!state.touching) { return; }
			state.touching = false;
			if (state.dragging) {
				state.dragging = false;
				state.fire("scrollenddrag");
				if (!cancelled) { state.beginMomentum(); }
			}
			if (!cancelled && state.enabled && state.refreshEnabled && state.pull >= 64 && !state.refreshing && !state.refreshPending) {
				state.refreshPending = true;
				state.fire("refresh");
				if (!state.refreshing) { state.refreshPending = false; }
			}
			state.pull = 0;
			state.showRefresh();
		};
		listen(el, "touchend", (e: DomEvent): void => { endTouch(e, false); }, false);
		listen(el, "touchcancel", (e: DomEvent): void => { endTouch(e, true); }, false);
		listen(el, "click", (e: DomEvent): void => {
			const focused = document.activeElement;
			if (state.taps === "always" || !inputNode(focused) || inputNode(e.target)) { return; }
			let target: Node | null = e.target;
			let handled = false;
			while (target !== null && target !== el) {
				if (presses.has(target as Node)) { handled = true; }
				target = (target as Node).parentNode;
			}
			if (state.taps === "handled" && (handled || e.defaultPrevented)) { return; }
			focused.blur();
			if (state.taps === "never") { e.preventDefault(); e.stopPropagation(); }
		}, true);
	}
	return {
		createElement: (tag: string): HostNode => {
			if (tag === "scrollview") {
				if (!scrollRule) {
					registerCss(SCROLL_CLASS, `.${SCROLL_CLASS}{overflow-x:hidden;overflow-y:auto}.neon-hide-horizontal::-webkit-scrollbar:horizontal{height:0}.neon-hide-vertical::-webkit-scrollbar:vertical{width:0}@keyframes neon-refresh-spin{to{transform:rotate(360deg)}}.neon-refresh-indicator[aria-busy=true]{animation:neon-refresh-spin 1s linear infinite}`);
					scrollRule = true;
				}
				const el = document.createElement("div");
				el.classList.add(SCROLL_CLASS);
				installScroll(el);
				return el as unknown as HostNode;
			}
			if (tag === "switch" || tag === "activityindicator" || tag === "image") {
				if (!controlRule) {
					registerCss("neon-controls", CONTROL_CSS);
					controlRule = true;
				}
				const control = document.createElement(tag === "image" ? "img" : tag === "switch" ? "input" : "div");
				if (tag === "switch") {
					control.setAttribute("type", "checkbox");
					control.setAttribute("role", "switch");
				}
				if (tag === "activityindicator") { control.classList.add("neon-activity"); }
				if (tag === "image") { control.classList.add("neon-image"); }
				controlKinds.set(control, tag);
				return control as unknown as HostNode;
			}
			return document.createElement(htmlTagFor(tag)) as unknown as HostNode;
		},
		createText: (s: string): HostNode => document.createTextNode(s) as unknown as HostNode,
		setText: (node: HostNode, s: string): void => {
			prepareVisibleContent();
			(node as unknown as Node).textContent = s;
		},
		setAttr: (node: HostNode, name: string, value: string): void => {
			prepareVisibleContent();
			const el = node as unknown as Node;
			writeDomAttr(el, name, value);
			if (name === "value" || name === "defaultValue") { return; }
			if (scrolls.has(el)) {
				if (name === "class") { el.classList.add(SCROLL_CLASS); }
				const state = scrolls.get(el) as DomScrollState;
				state.setOption(name, value);
				if (name === "maintainVisibleContentPosition") { trackKeeper(state); }
			}
		},
		removeAttr: (node: HostNode, name: string): void => {
			prepareVisibleContent();
			const el = node as unknown as Node;
			if (name === "value") { el.value = ""; }
			el.removeAttribute(domAttrName(name));
			if (scrolls.has(el)) {
				if (name === "class") { el.classList.add(SCROLL_CLASS); }
				const state = scrolls.get(el) as DomScrollState;
				state.setOption(name, "");
				if (name === "maintainVisibleContentPosition") { trackKeeper(state); }
			}
		},
		setStyle: (node: HostNode, style: Style): void => {
			prepareVisibleContent();
			applyCss((node as unknown as Node).style, style);
			const el = node as unknown as Node;
			if (scrolls.has(el)) { (scrolls.get(el) as DomScrollState).apply(); }
			scheduleLayouts();
		},
		setStyleProp: (node: HostNode, name: string, value: StyleValue): void => {
			prepareVisibleContent();
			applyCssProp((node as unknown as Node).style, name, value);
			const el = node as unknown as Node;
			if (scrolls.has(el)) { (scrolls.get(el) as DomScrollState).apply(); }
			scheduleLayouts();
		},
		setStyleClass: (node: HostNode, id: string, css: string): void => {
			prepareVisibleContent();
			registerCss(id, css);
			(node as unknown as Node).classList.add(id);
			scheduleLayouts();
		},
		addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {
			const type = eventType(name);
			// RN surface names project onto DOM listeners; e.type keeps the neon
			// spelling so handlers compare one vocabulary on every host.
			let domType = type;
			if (type === "press") { domType = "click"; }
			else if (type === "changetext") { domType = "input"; }
			else if (type === "submitediting") { domType = "keydown"; }
			else if (type === "valuechange") { domType = "change"; }
			const el = node as unknown as Node;
			if (type === "press" || type === "click") { presses.set(el, true); }
			if (scrolls.has(el) && (type === "scroll" || type === "scrollbegindrag" || type === "scrollenddrag" || type === "momentumscrollbegin" || type === "momentumscrollend" || type === "refresh")) {
				(scrolls.get(el) as DomScrollState).routes.push({ type, handler });
				return;
			}
			if (type === "layout") {
				const state = new DomLayoutState(el, handler);
				layouts.push(state);
				const observer = new ResizeObserver((): void => { if (state.active) { scheduleLayouts(); } });
				observer.observe(el);
				scheduleLayouts();
				keep(el, (): void => { state.active = false; observer.disconnect(); scheduleLayouts(); });
				return;
			}
			listen(el, domType, (de: DomEvent): void => {
				if (type === "submitediting" && (de.key !== "Enter" || de.isComposing)) { return; }
				const ev = neonEvent(type);
				ev.timeStamp = de.timeStamp;
				if (type === "valuechange") {
					ev.value = el.checked ? "true" : "false";
					handler(ev);
					if (switchValues.has(el)) { el.checked = switchValues.get(el) as boolean; }
					return;
				}
				if (type === "load" && controlKinds.has(el)) {
					ev.width = el.naturalWidth;
					ev.height = el.naturalHeight;
				}
				if (type === "error" && controlKinds.has(el)) { ev.value = "cannot load the image"; }
				if (type === "changetext" || type === "input" || type === "change" || type === "submitediting") { ev.value = de.target.value; }
				else if (type === "scroll") {
					ev.x = el.scrollLeft;
					ev.y = el.scrollTop;
					ev.width = el.offsetWidth;
					ev.height = el.offsetHeight;
					ev.contentWidth = el.scrollWidth;
					ev.contentHeight = el.scrollHeight;
				}
				else if (type === "keydown" || type === "keyup" || type === "keypress") {
					ev.key = de.key;
					ev.code = de.code;
					ev.altKey = de.altKey;
					ev.ctrlKey = de.ctrlKey;
					ev.metaKey = de.metaKey;
					ev.shiftKey = de.shiftKey;
					ev.repeat = de.repeat;
					ev.isComposing = de.isComposing;
				}
				else if (type === "press" || type === "click" || type === "dblclick" || type === "mousedown" || type === "mouseup" || type === "mousemove") {
					ev.x = de.clientX;
					ev.y = de.clientY;
				}
				handler(ev);
			}, false);
		},
		append: (parent: HostNode, child: HostNode): void => {
			prepareVisibleContent();
			(parent as unknown as Node).appendChild(child as unknown as Node);
			const el = parent as unknown as Node;
			if (scrolls.has(el)) { (scrolls.get(el) as DomScrollState).mountRefresh(); }
			scheduleLayouts();
		},
		insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null): void => {
			prepareVisibleContent();
			const el = parent as unknown as Node;
			const moved = node as unknown as Node;
			const before = ref === null ? null : (ref as unknown as Node);
			if (moved.isConnected && el.isConnected && Reflect.has(el, "moveBefore")) {
				el.moveBefore(moved, before);
			} else {
				el.insertBefore(moved, before);
			}
			if (scrolls.has(el)) { (scrolls.get(el) as DomScrollState).mountRefresh(); }
			scheduleLayouts();
		},
		removeChild: (parent: HostNode, node: HostNode): void => {
			prepareVisibleContent();
			release(node as unknown as Node);
			(parent as unknown as Node).removeChild(node as unknown as Node);
			scheduleLayouts();
		},
		nextSibling: (node: HostNode): HostNode | null => {
			return (node as unknown as Node).nextSibling as unknown as HostNode;
		},
		firstChild: (node: HostNode): HostNode | null => {
			return (node as unknown as Node).firstChild as unknown as HostNode;
		},
		cloneNode: (node: HostNode): HostNode => {
			return (node as unknown as Node).cloneNode(true) as unknown as HostNode;
		},
		voidArea: null,
		focus: (node: HostNode, focused: boolean): void => {
			const el = node as unknown as Node;
			if (focused) { el.focus(); } else { el.blur(); }
		},
		scrollTo: (node: HostNode, x: number, y: number, animated: boolean): void => {
			(node as unknown as Node).scroll({ left: x, top: y, behavior: animated ? "smooth" : "auto" });
		},
	};
}
