// The universal component vocabulary (user decision 2026-09-03): users write
// View/Text/TextInput/Pressable — RN-shaped, mobile-first; div/span are HTML
// details no user should meet. These are real components (the createComponent
// seam, so bodies run once at mount): each renders the LOWERCASE wire tag and
// every host translates that tag in its own createElement (browser:
// htmlTagFor; terminal: box; void ignores tags; mock records as written).
//
// Prop contract (component.test pins it): every value prop arrives as an
// Accessor<T> (style widens into bindStyleAll's () => Style, the
// call-based law's channel), while arrow literals, ref and on* cross RAW and
// take the field's flat type (handlers declare (e: NeonEvent) => void
// directly). `class` is the RN-web escape hatch, honored by the browser
// host's CSS-class channel, ignored by native.
//
// `onChangeText` stays RN-shaped here at RUNTIME — the component wraps the
// user's (text) => void around the host's (e: NeonEvent) => void contract, no
// macro machinery involved (the macro-side wrap in element covers the
// same name on raw lowercase tags).

import { NeonEvent } from "../render/event";
import { Style, layerStyles } from "../render/style";
import { onCleanup } from "../core/cleanup";
import { Accessor, accessor, untrack } from "../core/signal";
import { element } from "../macros/ui/element";
import { NeonNode, VAttr, VEvent, RefFn, hostElement, evt, dynAttr } from "../render/node";
import { Host, HostNode, VoidArea, TextSpan, TextMeasure } from "../render/hostTypes";
import { paragraphChildren } from "../render/paragraph";
import { VoidAreaHandle } from "../render/voidAreaHandle";
import { applyRef } from "../render/bind";
import { VoidSpace, getVoidScopeContext, getVoidAreaContext } from "../render/voidScope";
import { ElementHandle } from "../render/measure";
export { ElementHandle, DOMRect, MeasureRect, MeasureError } from "../render/measure";
import { visibleContentAttr } from "../render/visibleContent";
import {
	ResponderEntry,
	ResponderHandlers,
	ResponderParent,
	TouchPhase,
	parentResponder,
	responderTouch,
	responderScroll,
	responderUnmounted,
} from "../render/responder";
import { Pressability, PressRect } from "../render/pressability";

export type AccessibilityRole = "none" | "button" | "link" | "search" | "image" | "text" | "header" | "switch" | "checkbox" | "adjustable" | "progressbar" | "summary" | "alert" | "radio" | "radiogroup" | "tab" | "tablist" | "togglebutton" | "combobox" | "menu" | "menuitem";

export type Role =
	| "alert"
	| "alertdialog"
	| "application"
	| "article"
	| "banner"
	| "button"
	| "cell"
	| "checkbox"
	| "columnheader"
	| "combobox"
	| "complementary"
	| "contentinfo"
	| "definition"
	| "dialog"
	| "directory"
	| "document"
	| "feed"
	| "figure"
	| "form"
	| "grid"
	| "group"
	| "heading"
	| "img"
	| "link"
	| "list"
	| "listitem"
	| "log"
	| "main"
	| "marquee"
	| "math"
	| "menu"
	| "menubar"
	| "menuitem"
	| "meter"
	| "navigation"
	| "none"
	| "note"
	| "option"
	| "presentation"
	| "progressbar"
	| "radio"
	| "radiogroup"
	| "region"
	| "row"
	| "rowgroup"
	| "rowheader"
	| "scrollbar"
	| "searchbox"
	| "separator"
	| "slider"
	| "spinbutton"
	| "status"
	| "summary"
	| "switch"
	| "tab"
	| "table"
	| "tablist"
	| "tabpanel"
	| "term"
	| "timer"
	| "toolbar"
	| "tooltip"
	| "tree"
	| "treegrid"
	| "treeitem";

export type AccessibilityLiveRegion = "none" | "polite" | "assertive";
export type ImportantForAccessibility = "auto" | "yes" | "no" | "no-hide-descendants";

export interface AccessibilityValue {
	min?: number | null;
	max?: number | null;
	now?: number | null;
	text?: string | null;
}

export interface AccessibilityAction {
	name: string;
	label?: string | null;
}

// Parked on ~/metascript/.inbox/compiler/2026-10-21-boolean-or-string-literal-union-compares-wrong-on-c.md: React Native's `checked?: boolean | "mixed"` joins these fields once that card is fixed.
export interface AccessibilityState {
	disabled?: boolean | null;
	selected?: boolean | null;
	busy?: boolean | null;
	expanded?: boolean | null;
}

// Parked on ~/metascript/.inbox/compiler/2026-10-18-quoted-member-names-are-refused-outside-object-literals.md: React Native's aria-* aliases (aria-label, aria-busy, aria-checked, aria-disabled, aria-expanded, aria-selected, aria-hidden, aria-live, aria-modal, aria-valuemax/min/now/text, aria-labelledby) join these fields once a quoted interface field parses.
export interface AccessibilityProps {
	accessible?: Accessor<boolean> | null;
	accessibilityLabel?: Accessor<string> | null;
	accessibilityHint?: Accessor<string> | null;
	accessibilityRole?: Accessor<AccessibilityRole> | null;
	accessibilityState?: Accessor<AccessibilityState> | null;
	role?: Accessor<Role> | null;
	accessibilityValue?: Accessor<AccessibilityValue> | null;
	accessibilityLiveRegion?: Accessor<AccessibilityLiveRegion> | null;
	importantForAccessibility?: Accessor<ImportantForAccessibility> | null;
	accessibilityElementsHidden?: Accessor<boolean> | null;
	accessibilityViewIsModal?: Accessor<boolean> | null;
	accessibilityLabelledBy?: Accessor<string> | null;
	accessibilityActions?: Accessor<AccessibilityAction[]> | null;
	onAccessibilityAction?: ((e: NeonEvent) => void) | null;
	tabIndex?: Accessor<number> | null;
}

export interface HostProps extends AccessibilityProps {
	style?: Accessor<Style> | null;
	class?: Accessor<string> | null;
}

export function stringAttr(attrs: VAttr[], name: string, value: Accessor<string> | null): void {
	if (value === null) { return; }
	const read = value as () => string;
	attrs.push(dynAttr(name, (): string | null => read()));
}

export function flagAttr(attrs: VAttr[], name: string, value: Accessor<boolean> | null): void {
	if (value === null) { return; }
	const read = value as () => boolean;
	attrs.push(dynAttr(name, (): string | null => read() ? "true" : "false"));
}

function stateToken(out: string, on: boolean | null, token: string): string {
	if (on !== true) { return out; }
	return out === "" ? token : out + "," + token;
}

export function accessibilityStateTokens(state: AccessibilityState): string {
	let out = stateToken("", state.selected, "selected");
	out = stateToken(out, state.disabled, "disabled");
	out = stateToken(out, state.busy, "busy");
	out = stateToken(out, state.expanded, "expanded");
	out = stateToken(out, state.expanded === false, "collapsed");
	return out;
}

function accessibilityStateAttr(state: Accessor<AccessibilityState> | null): Accessor<string> | null {
	if (state === null) { return null; }
	const read = state as Accessor<AccessibilityState>;
	return accessor((): string => accessibilityStateTokens(read()));
}

function numberField(n: number | null): string {
	return n === null ? "" : Math.round(n as number).toString();
}

// "min,max,now,text": the numbers rounded and empty when absent, the text last so its commas stay its own.
export function accessibilityValueText(v: AccessibilityValue): string {
	return numberField(v.min) + "," + numberField(v.max) + "," + numberField(v.now) + "," + (v.text ?? "");
}

// RN View.js splits aria-labelledby on /\s*,\s*/ into the id list the host reads: ids joined by ",".
export function labelledByIds(ids: string): string {
	const out: string[] = [];
	for (const id of ids.split(",")) { out.push(id.trim()); }
	return out.join(",");
}

// One action per line, "name" or "name\tlabel"; a name or label holding either separator is refused.
export function accessibilityActionsText(actions: AccessibilityAction[]): string {
	const lines: string[] = [];
	for (const a of actions) {
		const label = a.label ?? "";
		if (a.name.includes("\n") || a.name.includes("\t") || label.includes("\n") || label.includes("\t")) {
			throw new Error(`accessibilityActions: name and label cannot hold a tab or a newline (${a.name})`);
		}
		lines.push(label === "" ? a.name : a.name + "\t" + label);
	}
	return lines.join("\n");
}

export function accessibilityAttrs(props: AccessibilityProps, attrs: VAttr[]): VAttr[] {
	flagAttr(attrs, "accessible", props.accessible);
	stringAttr(attrs, "accessibilityLabel", props.accessibilityLabel);
	stringAttr(attrs, "accessibilityHint", props.accessibilityHint);
	const role = props.accessibilityRole;
	if (role !== null) {
		const read = role as Accessor<AccessibilityRole>;
		attrs.push(dynAttr("accessibilityRole", (): string | null => { const v: AccessibilityRole = read(); return v; }));
	}
	stringAttr(attrs, "accessibilityState", accessibilityStateAttr(props.accessibilityState));
	const roleProp = props.role;
	if (roleProp !== null) {
		const read = roleProp as Accessor<Role>;
		attrs.push(dynAttr("role", (): string | null => { const v: Role = read(); return v; }));
	}
	const value = props.accessibilityValue;
	if (value !== null) {
		const read = value as Accessor<AccessibilityValue>;
		attrs.push(dynAttr("accessibilityValue", (): string | null => accessibilityValueText(read())));
	}
	const live = props.accessibilityLiveRegion;
	if (live !== null) {
		const read = live as Accessor<AccessibilityLiveRegion>;
		attrs.push(dynAttr("accessibilityLiveRegion", (): string | null => { const v: AccessibilityLiveRegion = read(); return v; }));
	}
	const important = props.importantForAccessibility;
	if (important !== null) {
		const read = important as Accessor<ImportantForAccessibility>;
		attrs.push(dynAttr("importantForAccessibility", (): string | null => { const v: ImportantForAccessibility = read(); return v; }));
	}
	flagAttr(attrs, "accessibilityElementsHidden", props.accessibilityElementsHidden);
	flagAttr(attrs, "accessibilityViewIsModal", props.accessibilityViewIsModal);
	const labelledBy = props.accessibilityLabelledBy;
	if (labelledBy !== null) {
		const read = labelledBy as Accessor<string>;
		attrs.push(dynAttr("accessibilityLabelledBy", (): string | null => labelledByIds(read())));
	}
	const actions = props.accessibilityActions;
	if (actions !== null) {
		const read = actions as Accessor<AccessibilityAction[]>;
		attrs.push(dynAttr("accessibilityActions", (): string | null => accessibilityActionsText(read())));
	}
	const tab = props.tabIndex;
	if (tab !== null) {
		const read = tab as Accessor<number>;
		attrs.push(dynAttr("focusable", (): string | null => read() === 0 ? "true" : "false"));
	}
	return attrs;
}

export function accessibilityEvents(props: AccessibilityProps, evts: VEvent[]): VEvent[] {
	if (props.onAccessibilityAction !== null) { evts.push(evt("onAccessibilityAction", props.onAccessibilityAction as (e: NeonEvent) => void)); }
	return evts;
}

function primitive(tag: string, props: HostProps, attrs: VAttr[], evts: VEvent[], kids: NeonNode | null, rawRef: RefFn | null = null, ref: ((handle: ViewHandle) => void) | null = null): NeonNode {
	if (props.class !== null) {
		const cls = props.class as () => string;
		attrs.push(dynAttr("class", () => cls()));
	}
	accessibilityAttrs(props, attrs);
	accessibilityEvents(props, evts);
	let style: (() => Style) | null = null;
	if (props.style !== null) { style = props.style as () => Style; }
	const handle = viewRef(ref);
	const grab = viewGrab(handle);
	const take: RefFn | null = rawRef === null ? grab : grab === null ? rawRef : (n: HostNode): void => {
		(rawRef as RefFn)(n);
		(grab as RefFn)(n);
	};
	return viewMount(handle, hostElement(tag, attrs, evts, kids, style, take));
}

// Where the IME candidate window goes, in the component's own layout points.
export interface ImeRect {
	x: number;
	y: number;
	width: number;
	height: number;
}

export interface InteractiveProps extends HostProps {
	focusable?: Accessor<boolean> | null;
	imeRect?: Accessor<ImeRect> | null;
	onTextInput?: ((e: NeonEvent) => void) | null;
	onPreedit?: ((e: NeonEvent) => void) | null;
	onPointerDown?: ((e: NeonEvent) => void) | null;
	onPointerMove?: ((e: NeonEvent) => void) | null;
	onPointerUp?: ((e: NeonEvent) => void) | null;
	onWheel?: ((e: NeonEvent) => void) | null;
	onKeyDown?: ((e: NeonEvent) => void) | null;
	onKeyUp?: ((e: NeonEvent) => void) | null;
	onFocus?: ((e: NeonEvent) => void) | null;
	onBlur?: ((e: NeonEvent) => void) | null;
	onLayout?: ((e: NeonEvent) => void) | null;
}

function interactiveEvents(props: InteractiveProps, evts: VEvent[]): VEvent[] {
	if (props.onKeyDown !== null) { evts.push(evt("onKeyDown", props.onKeyDown as (e: NeonEvent) => void)); }
	if (props.onKeyUp !== null) { evts.push(evt("onKeyUp", props.onKeyUp as (e: NeonEvent) => void)); }
	if (props.onFocus !== null) { evts.push(evt("onFocus", props.onFocus as (e: NeonEvent) => void)); }
	if (props.onBlur !== null) { evts.push(evt("onBlur", props.onBlur as (e: NeonEvent) => void)); }
	if (props.onLayout !== null) { evts.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	if (props.onTextInput !== null) { evts.push(evt("onTextInput", props.onTextInput as (e: NeonEvent) => void)); }
	if (props.onPreedit !== null) { evts.push(evt("onPreedit", props.onPreedit as (e: NeonEvent) => void)); }
	if (props.onPointerDown !== null) { evts.push(evt("onPointerDown", props.onPointerDown as (e: NeonEvent) => void)); }
	if (props.onPointerMove !== null) { evts.push(evt("onPointerMove", props.onPointerMove as (e: NeonEvent) => void)); }
	if (props.onPointerUp !== null) { evts.push(evt("onPointerUp", props.onPointerUp as (e: NeonEvent) => void)); }
	if (props.onWheel !== null) { evts.push(evt("onWheel", props.onWheel as (e: NeonEvent) => void)); }
	return evts;
}

function interactiveAttrs(props: InteractiveProps, attrs: VAttr[]): VAttr[] {
	if (props.tabIndex === null) { flagAttr(attrs, "focusable", props.focusable); }
	const rect = props.imeRect;
	if (rect !== null) {
		const read = rect as Accessor<ImeRect>;
		attrs.push(dynAttr("imeRect", (): string | null => {
			const r = read();
			return r.x.toString() + "," + r.y.toString() + "," + r.width.toString() + "," + r.height.toString();
		}));
	}
	return attrs;
}

export interface ViewProps extends InteractiveProps {
	ref?: ((handle: ViewHandle) => void) | null;
	onTouchStart?: ((e: NeonEvent) => void) | null;
	onTouchMove?: ((e: NeonEvent) => void) | null;
	onTouchEnd?: ((e: NeonEvent) => void) | null;
	onTouchCancel?: ((e: NeonEvent) => void) | null;
	onStartShouldSetResponder?: ((e: NeonEvent) => boolean) | null;
	onStartShouldSetResponderCapture?: ((e: NeonEvent) => boolean) | null;
	onMoveShouldSetResponder?: ((e: NeonEvent) => boolean) | null;
	onMoveShouldSetResponderCapture?: ((e: NeonEvent) => boolean) | null;
	onResponderGrant?: ((e: NeonEvent) => boolean) | null;
	onResponderReject?: ((e: NeonEvent) => void) | null;
	onResponderStart?: ((e: NeonEvent) => void) | null;
	onResponderMove?: ((e: NeonEvent) => void) | null;
	onResponderEnd?: ((e: NeonEvent) => void) | null;
	onResponderRelease?: ((e: NeonEvent) => void) | null;
	onResponderTerminate?: ((e: NeonEvent) => void) | null;
	onResponderTerminationRequest?: ((e: NeonEvent) => boolean) | null;
	children?: NeonNode | null;
}

function responderHandlers(props: ViewProps): ResponderHandlers | null {
	const handlers: ResponderHandlers = {
		onStartShouldSetResponder: props.onStartShouldSetResponder,
		onStartShouldSetResponderCapture: props.onStartShouldSetResponderCapture,
		onMoveShouldSetResponder: props.onMoveShouldSetResponder,
		onMoveShouldSetResponderCapture: props.onMoveShouldSetResponderCapture,
		onResponderGrant: props.onResponderGrant,
		onResponderReject: props.onResponderReject,
		onResponderStart: props.onResponderStart,
		onResponderMove: props.onResponderMove,
		onResponderEnd: props.onResponderEnd,
		onResponderRelease: props.onResponderRelease,
		onResponderTerminate: props.onResponderTerminate,
		onResponderTerminationRequest: props.onResponderTerminationRequest,
	};
	const negotiates = handlers.onStartShouldSetResponder !== null || handlers.onStartShouldSetResponderCapture !== null ||
		handlers.onMoveShouldSetResponder !== null || handlers.onMoveShouldSetResponderCapture !== null;
	return negotiates ? handlers : null;
}

function touchEvent(name: string, user: ((e: NeonEvent) => void) | null, entry: ResponderEntry | null, phase: TouchPhase): VEvent | null {
	if (user === null && entry === null) { return null; }
	if (entry === null) { return evt(name, user as (e: NeonEvent) => void); }
	return {
		name,
		lifecycle: (e: NeonEvent): void => { responderTouch(entry as ResponderEntry, phase, e); },
		handler: user === null ? (e: NeonEvent): void => {} : user as (e: NeonEvent) => void,
	};
}

function spanTouch(entry: ResponderEntry): (name: string, e: NeonEvent) => void {
	return (name: string, e: NeonEvent): void => {
		match (name) {
			"onTouchStart" => { responderTouch(entry, TouchPhase.Start, e); },
			"onTouchMove" => { responderTouch(entry, TouchPhase.Move, e); },
			"onTouchEnd" => { responderTouch(entry, TouchPhase.End, e); },
			"onTouchCancel" => { responderTouch(entry, TouchPhase.Cancel, e); },
			_ => { throw new Error(`${name} is no touch a span takes`); },
		}
	};
}

// A data span with onPress is a Pressability responder of its own, as the nested Text it stands for is.
function dataSpans(read: Accessor<TextSpan[]>): NeonNode {
	return (host: Host, node: HostNode, before: HostNode | null): void => {
		const parent = parentResponder();
		const entries: ResponderEntry[] = [];
		const machines: Pressability[] = [];
		const routed: TextSpan[] = [];
		let latest: TextSpan[] = [];
		onCleanup((): void => {
			for (let i = 0; i < entries.length; i += 1) {
				responderUnmounted(entries[i]);
				machines[i].reset();
			}
		});
		const route = (at: int32): TextSpan => {
			while (routed.length <= at) {
				const index = routed.length;
				const pressability = new Pressability({
					cancelable: null, hitSlop: null, delayLongPress: null,
					onPress: (e: NeonEvent): void => {
						const press = index < latest.length ? latest[index].onPress : null;
						if (press !== null) { (press as (e: NeonEvent) => void)(e); }
					},
					onPressIn: null, onPressOut: null, onLongPress: null, onHoverIn: null, onHoverOut: null,
				});
				const entry = new ResponderEntry(pressability.responderHandlers(), parent);
				entry.host = host;
				entry.node = node;
				pressability.attach(host, node);
				entries.push(entry);
				machines.push(pressability);
				routed.push({ text: "", onPress: (e: NeonEvent): void => { pressability.click(e); }, onTouch: spanTouch(entry) });
			}
			return routed[at];
		};
		const spans = accessor((): TextSpan[] => {
			latest = read();
			const out: TextSpan[] = [];
			for (let i = 0; i < latest.length; i += 1) {
				const s = latest[i];
				if (s.onPress === null) {
					out.push(s);
					continue;
				}
				const r = route(i as int32);
				out.push({ text: s.text, style: s.style, onPress: r.onPress, onTouch: r.onTouch });
			}
			return out;
		});
		paragraphChildren(null, spans)(host, node, before);
	};
}

export class ViewHandle extends ElementHandle {
	private host: Host;
	private mounted: () => boolean;

	constructor(host: Host, node: HostNode, mounted: () => boolean) {
		super(host, node, mounted);
		this.host = host;
		this.mounted = mounted;
	}

	focus(): void { this.setFocused(true); }
	blur(): void { this.setFocused(false); }

	measureText(text: string, style: Style): TextMeasure {
		if (!this.mounted()) { throw "View.measureText was called after the View unmounted"; }
		const measure = this.host.measureText;
		if (measure === null) { throw "View.measureText needs a host that measures text, and this host has none"; }
		return (measure as (t: string, s: Style) => TextMeasure)(text, style);
	}

	private setFocused(focused: boolean): void {
		if (!this.mounted()) {
			when (debug) { console.warn(`View.${focused ? "focus" : "blur"} was called after the View unmounted, so it does nothing`); }
			return;
		}
		const hostFocus = this.host.focus;
		if (hostFocus === null) { throw "View.focus needs a host with the focus capability, and this host has none"; }
		(hostFocus as (n: HostNode, f: boolean) => void)(this.node, focused);
	}
}

export interface ViewRef {
	grab: RefFn;
	mount: (node: NeonNode) => NeonNode;
}

export function viewRef(ref: ((handle: ViewHandle) => void) | null): ViewRef | null {
	if (ref === null) { return null; }
	const user = ref as (handle: ViewHandle) => void;
	let on: Host | null = null;
	return {
		grab: (n: HostNode): void => {
			let mounted = true;
			onCleanup((): void => { mounted = false; });
			user(new ViewHandle(on as Host, n, (): boolean => mounted));
		},
		mount: (node: NeonNode): NeonNode => (host: Host, parent: HostNode, before: HostNode | null): void => {
			on = host;
			node(host, parent, before);
		},
	};
}

export function viewGrab(handle: ViewRef | null): RefFn | null {
	return handle === null ? null : (handle as ViewRef).grab;
}

export function viewMount(handle: ViewRef | null, node: NeonNode): NeonNode {
	return handle === null ? node : (handle as ViewRef).mount(node);
}

export function View(props: ViewProps): NeonNode {
	const handlers = responderHandlers(props);
	const evts = interactiveEvents(props, []);
	const entry = handlers === null ? null : new ResponderEntry(handlers as ResponderHandlers, parentResponder());
	const touches: VEvent[] = [];
	const start = touchEvent("onTouchStart", props.onTouchStart, entry, TouchPhase.Start);
	const move = touchEvent("onTouchMove", props.onTouchMove, entry, TouchPhase.Move);
	const end = touchEvent("onTouchEnd", props.onTouchEnd, entry, TouchPhase.End);
	const cancel = touchEvent("onTouchCancel", props.onTouchCancel, entry, TouchPhase.Cancel);
	if (start !== null) { evts.push(start as VEvent); }
	if (move !== null) { evts.push(move as VEvent); }
	if (end !== null) { evts.push(end as VEvent); }
	if (cancel !== null) { evts.push(cancel as VEvent); }
	const attrs = interactiveAttrs(props, []);
	const kids = props.children;
	const provided: NeonNode | null = entry === null || kids === null ? kids : ResponderParent.provider({
		value: accessor((): ResponderEntry | null => entry),
		children: kids as NeonNode,
	});
	const take: RefFn | null = entry === null ? null : (node: HostNode): void => { (entry as ResponderEntry).node = node; };
	const view = primitive("view", props, attrs, evts, provided, take, props.ref);
	if (entry === null) { return view; }
	const owner = entry as ResponderEntry;
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		owner.host = host;
		onCleanup((): void => { responderUnmounted(owner); });
		view(host, parent, before);
	};
}

export type EllipsizeMode = "head" | "middle" | "tail" | "clip";

export interface TextProps extends HostProps {
	ref?: ((handle: ViewHandle) => void) | null;
	numberOfLines?: Accessor<number> | null;
	ellipsizeMode?: Accessor<EllipsizeMode> | null;
	selectable?: Accessor<boolean> | null;
	// Neon's own, for terminals and editors: every grapheme takes this many points, on the Void host only.
	cellWidth?: Accessor<number> | null;
	// The grid's widths beside cellWidth: one entry per UTF-8 byte of the text, 1 or 2 where a cell starts and 0 for its other bytes.
	cellWidths?: Accessor<uint8[]> | null;
	// The data form of nested Texts, for content that already is data (terminal and editor lines).
	spans?: Accessor<TextSpan[]> | null;
	onPress?: ((e: NeonEvent) => void) | null;
	children?: NeonNode | null;
}

function accessibleText(props: AccessibilityProps): Accessor<string> | null {
	const flag = props.accessible;
	if (flag === null) { return null; }
	const read = flag as Accessor<boolean>;
	return accessor((): string => read() ? "true" : "false");
}

function cellDigits(widths: uint8[]): string {
	const digits: string[] = [];
	for (const w of widths) {
		if (w > 2) { throw new Error(`cellWidths: a grid cell is 1 or 2 wide and 0 after its first byte, not ${w}`); }
		digits.push(w.toString());
	}
	return digits.join("");
}

export function Text(props: TextProps): NeonNode {
	const lines = props.numberOfLines;
	const ellipsize = props.ellipsizeMode;
	const press = props.onPress;
	const cell = props.cellWidth;
	const widths = props.cellWidths;
	const spans = props.spans;
	if (spans !== null && props.children !== null) { throw new Error("<Text> takes spans or children, not both"); }
	if (widths !== null && cell === null) { throw new Error("<Text> cellWidths needs cellWidth"); }
	const attrs: VAttr[] = [];
	if (lines !== null) {
		const read = lines as Accessor<number>;
		attrs.push(dynAttr("numberOfLines", (): string | null => Math.max(0, Math.round(read())).toString()));
	}
	if (ellipsize !== null) {
		const read = ellipsize as Accessor<EllipsizeMode>;
		attrs.push(dynAttr("ellipsizeMode", (): string | null => { const m: EllipsizeMode = read(); return m; }));
	}
	flagAttr(attrs, "selectable", props.selectable);
	if (cell !== null) {
		const read = cell as Accessor<number>;
		attrs.push(dynAttr("cellWidth", (): string | null => read().toString()));
	}
	if (widths !== null) {
		const read = widths as Accessor<uint8[]>;
		attrs.push(dynAttr("cellWidths", (): string | null => cellDigits(read())));
	}
	const kids = spans === null ? paragraphChildren(props.children, null) : dataSpans(spans as Accessor<TextSpan[]>);
	if (press === null) { return primitive("text", props, attrs, [], kids, null, props.ref); }
	const pressability = new Pressability({
		cancelable: null, hitSlop: null, delayLongPress: null,
		onPress: press, onPressIn: null, onPressOut: null, onLongPress: null, onHoverIn: null, onHoverOut: null,
	});
	return withPressability(pressability, [], kids, (evts: VEvent[], children: NeonNode | null, grab: RefFn): NeonNode =>
		primitive("text", props, attrs, evts, children, grab, props.ref));
}

// RN usePressability: the press machine joins the responder system through the element's own touches.
function withPressability(pressability: Pressability, evts: VEvent[], kids: NeonNode | null,
	build: (evts: VEvent[], kids: NeonNode | null, grab: RefFn) => NeonNode): NeonNode {
	const entry = new ResponderEntry(pressability.responderHandlers(), parentResponder());
	evts.push(touchEvent("onTouchStart", null, entry, TouchPhase.Start) as VEvent);
	evts.push(touchEvent("onTouchMove", null, entry, TouchPhase.Move) as VEvent);
	evts.push(touchEvent("onTouchEnd", null, entry, TouchPhase.End) as VEvent);
	evts.push(touchEvent("onTouchCancel", null, entry, TouchPhase.Cancel) as VEvent);
	evts.push(evt("onPress", (e: NeonEvent): void => { pressability.click(e); }));
	const provided: NeonNode | null = kids === null ? null : ResponderParent.provider({
		value: accessor((): ResponderEntry | null => entry),
		children: kids as NeonNode,
	});
	const node = build(evts, provided, (n: HostNode): void => {
		entry.node = n;
		pressability.attach(entry.host as Host, n);
	});
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		entry.host = host;
		onCleanup((): void => {
			responderUnmounted(entry);
			pressability.reset();
		});
		node(host, parent, before);
	};
}

// RN Insets: how far each edge of a touch target reaches past the view.
export interface Insets {
	top?: number | null;
	left?: number | null;
	bottom?: number | null;
	right?: number | null;
}

// RN PressableAndroidRippleConfig; a no-op off Android.
export interface AndroidRipple {
	color?: string | null;
	borderless?: boolean | null;
	radius?: number | null;
}

function insetsRect(slop: number | Insets): PressRect {
	if (typeof slop === "number") {
		const all = Math.max(0, slop as number);
		return { top: all, left: all, bottom: all, right: all };
	}
	const { top = 0, left = 0, bottom = 0, right = 0 } = slop as Insets;
	return { top: Math.max(0, top), left: Math.max(0, left), bottom: Math.max(0, bottom), right: Math.max(0, right) };
}

function insetsAttr(slop: number | Insets): string {
	const r = insetsRect(slop);
	return `${r.top},${r.left},${r.bottom},${r.right}`;
}

function rippleAttr(ripple: AndroidRipple): string {
	const { color = "", borderless = false, radius = -1 } = ripple;
	return `${color},${borderless ? "true" : "false"},${radius >= 0 ? radius.toString() : ""}`;
}

interface PressableProps extends HostProps {
	ref?: ((handle: ViewHandle) => void) | null;
	hitSlop?: Accessor<number | Insets> | null;
	android_ripple?: Accessor<AndroidRipple> | null;
	onPress?: ((e: NeonEvent) => void) | null;
	onPressIn?: ((e: NeonEvent) => void) | null;
	onPressOut?: ((e: NeonEvent) => void) | null;
	onLongPress?: ((e: NeonEvent) => void) | null;
	onHoverIn?: ((e: NeonEvent) => void) | null;
	onHoverOut?: ((e: NeonEvent) => void) | null;
	onLayout?: ((e: NeonEvent) => void) | null;
	delayLongPress?: Accessor<number> | null;
	cancelable?: Accessor<boolean> | null;
	children?: NeonNode | null;
}

export function Pressable(props: PressableProps): NeonNode {
	const slop = props.hitSlop;
	const pressability = new Pressability({
		cancelable: props.cancelable,
		hitSlop: slop === null ? null : (): PressRect => insetsRect((slop as Accessor<number | Insets>)()),
		delayLongPress: props.delayLongPress,
		onPress: props.onPress, onPressIn: props.onPressIn, onPressOut: props.onPressOut, onLongPress: props.onLongPress,
		onHoverIn: props.onHoverIn, onHoverOut: props.onHoverOut,
	});
	// RN Pressable.js: `accessible: accessible !== false`, so a Pressable is one
	// accessibility element whose label the host composes from its texts.
	const declared = accessibleText(props);
	const accessible = declared === null ? accessor((): string => "true") : declared as Accessor<string>;
	const hitSlop: Accessor<string> | null = slop === null ? null : accessor((): string => insetsAttr((slop as Accessor<number | Insets>)()));
	const ripple = props.android_ripple;
	const androidRipple: Accessor<string> | null = ripple === null ? null : accessor((): string => rippleAttr((ripple as Accessor<AndroidRipple>)()));
	const attrs: VAttr[] = [];
	stringAttr(attrs, "hitSlop", hitSlop);
	stringAttr(attrs, "androidRipple", androidRipple);
	const evts: VEvent[] = [];
	if (props.onLayout !== null) { evts.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	if (props.onHoverIn !== null) { evts.push(evt("onPointerEnter", (e: NeonEvent): void => { pressability.pointerEnter(e); })); }
	if (props.onHoverOut !== null) { evts.push(evt("onPointerLeave", (e: NeonEvent): void => { pressability.pointerLeave(e); })); }
	return withPressability(pressability, evts, props.children, (all: VEvent[], kids: NeonNode | null, grab: RefFn): NeonNode =>
		primitive("pressable", { ...props, accessible: accessor((): boolean => accessible() === "true") }, attrs, all, kids, grab, props.ref));
}

export interface ScrollToOptions {
	x?: number | null;
	y?: number | null;
	animated?: boolean | null;
}

export class ScrollViewHandle extends ElementHandle {
	private host: Host;
	private mounted: () => boolean;

	constructor(host: Host, node: HostNode, mounted: () => boolean) {
		super(host, node, mounted);
		this.host = host;
		this.mounted = mounted;
	}

	scrollTo(options: ScrollToOptions): void {
		if (!this.mounted()) { throw "ScrollView.scrollTo was called after the ScrollView unmounted"; }
		const hostScrollTo = this.host.scrollTo;
		if (hostScrollTo === null) { throw "ScrollView.scrollTo needs a host with the scrollTo capability, and this host has none"; }
		const { x = 0, y = 0, animated = true } = options;
		(hostScrollTo as (n: HostNode, x: number, y: number, animated: boolean) => void)(this.node, x, y, animated);
	}
}

export interface MaintainVisibleContentPosition {
	minIndexForVisible: number;
	autoscrollToTopThreshold?: number | null;
}

export type KeyboardDismissMode = "none" | "on-drag" | "interactive";
export type KeyboardShouldPersistTaps = "never" | "always" | "handled";

export interface ScrollViewProps {
	style?: Accessor<Style> | null;
	contentContainerStyle?: Accessor<Style> | null;
	class?: Accessor<string> | null;
	ref?: ((handle: ScrollViewHandle) => void) | null;
	onScroll?: ((e: NeonEvent) => void) | null;
	scrollEventThrottle?: Accessor<number> | null;
	onLayout?: ((e: NeonEvent) => void) | null;
	onContentSizeChange?: ((width: number, height: number) => void) | null;
	horizontal?: Accessor<boolean> | null;
	scrollEnabled?: Accessor<boolean> | null;
	showsHorizontalScrollIndicator?: Accessor<boolean> | null;
	showsVerticalScrollIndicator?: Accessor<boolean> | null;
	pagingEnabled?: Accessor<boolean> | null;
	keyboardDismissMode?: Accessor<KeyboardDismissMode> | null;
	keyboardShouldPersistTaps?: Accessor<KeyboardShouldPersistTaps> | null;
	onScrollBeginDrag?: ((e: NeonEvent) => void) | null;
	onScrollEndDrag?: ((e: NeonEvent) => void) | null;
	onMomentumScrollBegin?: ((e: NeonEvent) => void) | null;
	onMomentumScrollEnd?: ((e: NeonEvent) => void) | null;
	onRefresh?: (() => void) | null;
	refreshing?: Accessor<boolean> | null;
	maintainVisibleContentPosition?: Accessor<MaintainVisibleContentPosition> | null;
	refreshControl?: NeonNode | null;
	children?: NeonNode | null;
}

// RN scrollEventThrottle: up to 16 ms means every event on iOS and Android
// (RCTScrollViewComponentView.mm:375-387, ReactScrollViewHelper.kt:116-124).
const EVERY_FRAME_MS = 16;

// RN ScrollView.js styles.baseVertical, composed under the author's style.
const SCROLL_BASE: Style = { display: "flex", flexGrow: 1, flexShrink: 1, flexDirection: "column", overflow: "scroll" };
const SCROLL_HORIZONTAL: Style = { display: "flex", flexGrow: 1, flexShrink: 1, flexDirection: "row", overflow: "scroll" };

export function ScrollView(props: ScrollViewProps): NeonNode {
	const evts: VEvent[] = [];
	const attrs: VAttr[] = [];
	const horizontal = props.horizontal;
	if (horizontal !== null) { attrs.push(dynAttr("horizontal", (): string | null => `${(horizontal as () => boolean)()}`)); }
	const enabled = props.scrollEnabled;
	if (enabled !== null) { attrs.push(dynAttr("scrollEnabled", (): string | null => `${(enabled as () => boolean)()}`)); }
	const horizontalIndicator = props.showsHorizontalScrollIndicator;
	if (horizontalIndicator !== null) { attrs.push(dynAttr("showsHorizontalScrollIndicator", (): string | null => `${(horizontalIndicator as () => boolean)()}`)); }
	const verticalIndicator = props.showsVerticalScrollIndicator;
	if (verticalIndicator !== null) { attrs.push(dynAttr("showsVerticalScrollIndicator", (): string | null => `${(verticalIndicator as () => boolean)()}`)); }
	const paging = props.pagingEnabled;
	if (paging !== null) { attrs.push(dynAttr("pagingEnabled", (): string | null => `${(paging as () => boolean)()}`)); }
	const dismiss = props.keyboardDismissMode;
	if (dismiss !== null) { attrs.push(dynAttr("keyboardDismissMode", (): string | null => (dismiss as () => string)())); }
	const taps = props.keyboardShouldPersistTaps;
	if (taps !== null) { attrs.push(dynAttr("keyboardShouldPersistTaps", (): string | null => (taps as () => string)())); }
	const refreshing = props.refreshing;
	if (refreshing !== null) { attrs.push(dynAttr("refreshing", (): string | null => `${(refreshing as () => boolean)()}`)); }
	const keep = props.maintainVisibleContentPosition;
	if (keep !== null) {
		attrs.push(dynAttr("maintainVisibleContentPosition", (): string | null => {
			const position = (keep as Accessor<MaintainVisibleContentPosition>)();
			const threshold = position.autoscrollToTopThreshold;
			return visibleContentAttr(position.minIndexForVisible, threshold);
		}));
	}
	if (props.onScrollBeginDrag !== null) { evts.push(evt("onScrollBeginDrag", props.onScrollBeginDrag as (e: NeonEvent) => void)); }
	if (props.onScrollEndDrag !== null) { evts.push(evt("onScrollEndDrag", props.onScrollEndDrag as (e: NeonEvent) => void)); }
	if (props.onMomentumScrollBegin !== null) { evts.push(evt("onMomentumScrollBegin", props.onMomentumScrollBegin as (e: NeonEvent) => void)); }
	if (props.onMomentumScrollEnd !== null) { evts.push(evt("onMomentumScrollEnd", props.onMomentumScrollEnd as (e: NeonEvent) => void)); }
	const refresh = props.onRefresh;
	if (refresh !== null && refreshing === null) { throw "ScrollView: refreshing must be provided with onRefresh"; }
	if (refresh !== null) {
		attrs.push(dynAttr("refreshEnabled", (): string | null => "true"));
		evts.push(evt("onRefresh", (e: NeonEvent): void => { (refresh as () => void)(); }));
	}
	const userScroll = props.onScroll;
	const throttle = props.scrollEventThrottle;
	if (props.onLayout !== null) { evts.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	const sizeChange = props.onContentSizeChange;
	const userContentStyle = props.contentContainerStyle;
	const contentStyle: Accessor<Style> = accessor((): Style => {
		const base: Style = { display: "flex", flexShrink: 0, flexDirection: horizontal !== null && (horizontal as () => boolean)() ? "row" : "column" };
		return userContentStyle === null ? base : layerStyles([base, (userContentStyle as () => Style)()]);
	});
	const content = sizeChange === null
		? element(<view style={contentStyle}>{props.children}</view>)
		: element(<view style={contentStyle} onLayout={(e: NeonEvent): void => { (sizeChange as (width: number, height: number) => void)(e.width, e.height); }}>{props.children}</view>);
	const userRef = props.ref;
	const refreshControl = props.refreshControl;
	const userStyle = props.style;
	const className = props.class;
	const style: Accessor<Style> = accessor((): Style => {
		const base = horizontal !== null && (horizontal as () => boolean)() ? SCROLL_HORIZONTAL : SCROLL_BASE;
		return userStyle === null ? base : layerStyles([base, (userStyle as () => Style)()]);
	});
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		let observedScroll = false;
		const handlers: ResponderHandlers = {
			onStartShouldSetResponder: null,
			onStartShouldSetResponderCapture: null,
			onMoveShouldSetResponder: null,
			onMoveShouldSetResponderCapture: null,
			onResponderGrant: (e: NeonEvent): boolean => { observedScroll = false; return false; },
			onResponderReject: null,
			onResponderStart: null,
			onResponderMove: null,
			onResponderEnd: null,
			onResponderRelease: null,
			onResponderTerminate: null,
			onResponderTerminationRequest: (e: NeonEvent): boolean => !observedScroll,
		};
		const entry = new ResponderEntry(handlers, parentResponder());
		entry.host = host;
		onCleanup((): void => { responderUnmounted(entry); });
		const mountEvents = evts.slice(0, evts.length);
		mountEvents.push(touchEvent("onTouchStart", null, entry, TouchPhase.Start) as VEvent);
		mountEvents.push(touchEvent("onTouchMove", null, entry, TouchPhase.Move) as VEvent);
		mountEvents.push(touchEvent("onTouchEnd", null, entry, TouchPhase.End) as VEvent);
		mountEvents.push(touchEvent("onTouchCancel", null, entry, TouchPhase.Cancel) as VEvent);
		let last = -1.0;
		mountEvents.push(evt("onScroll", (e: NeonEvent): void => {
			if (!entry.mounted) { return; }
			if (responderScroll(entry, e)) { observedScroll = true; }
			if (!entry.mounted || userScroll === null) { return; }
			const every = throttle === null ? 0 : (throttle as () => number)();
			if (every > EVERY_FRAME_MS) {
				const now = performance.now();
				if (last >= 0 && now - last < every) { return; }
				last = now;
			}
			(userScroll as (e: NeonEvent) => void)(e);
		}));
		const inner: NeonNode = (h: Host, node: HostNode, at: HostNode | null): void => {
			entry.node = node;
			content(h, node, at);
			if (refreshControl !== null) { (refreshControl as NeonNode)(h, node, null); }
			if (userRef !== null) {
				let mounted = true;
				onCleanup((): void => { mounted = false; });
				(userRef as (h: ScrollViewHandle) => void)(new ScrollViewHandle(h, node, (): boolean => mounted));
			}
		};
		const provided = ResponderParent.provider({ value: accessor((): ResponderEntry | null => entry), children: inner });
		const mountAttrs = attrs.slice(0, attrs.length);
		primitive("scrollview", { style, class: className }, mountAttrs, mountEvents, provided, null)(host, parent, before);
	};
}

export type KeyboardType = "default" | "numeric" | "number-pad" | "decimal-pad" | "email-address" | "phone-pad" | "url";
export type ReturnKeyType = "done" | "go" | "next" | "search" | "send";
export type AutoCapitalize = "none" | "sentences" | "words" | "characters";

export class TextInputHandle extends ElementHandle {
	private host: Host;
	private focused: () => boolean;
	private mounted: () => boolean;

	constructor(host: Host, node: HostNode, focused: () => boolean, mounted: () => boolean) {
		super(host, node, mounted);
		this.host = host;
		this.focused = focused;
		this.mounted = mounted;
	}

	focus(): void { this.setFocused(true); }
	blur(): void { this.setFocused(false); }
	isFocused(): boolean { return this.focused(); }

	clear(): void {
		if (!this.mounted()) { throw "TextInput.clear was called after the TextInput unmounted"; }
		this.host.setAttr(this.node, "value", "");
	}

	private setFocused(focused: boolean): void {
		if (!this.mounted()) { throw "TextInput focus was changed after the TextInput unmounted"; }
		const hostFocus = this.host.focus;
		if (hostFocus === null) { throw "TextInput.focus needs a host with the focus capability, and this host has none"; }
		(hostFocus as (n: HostNode, f: boolean) => void)(this.node, focused);
	}
}

// RN TextInput selection: character offsets, end exclusive; start === end is a caret.
export interface TextSelection {
	start: number;
	end?: number | null;
}

function selectionOf(value: string): TextSelection {
	const parts = value.split(",");
	const start: number = parts.length > 0 ? parseFloat(parts[0]) : 0;
	const end: number = parts.length > 1 ? parseFloat(parts[1]) : start;
	return { start, end };
}

interface TextInputProps extends AccessibilityProps {
	style?: Accessor<Style> | null;
	class?: Accessor<string> | null;
	ref?: ((handle: TextInputHandle) => void) | null;
	value?: Accessor<string> | null;
	defaultValue?: Accessor<string> | null;
	placeholder?: Accessor<string> | null;
	placeholderTextColor?: Accessor<string> | null;
	editable?: Accessor<boolean> | null;
	secureTextEntry?: Accessor<boolean> | null;
	multiline?: Accessor<boolean> | null;
	autoFocus?: Accessor<boolean> | null;
	autoCorrect?: Accessor<boolean> | null;
	autoCapitalize?: Accessor<AutoCapitalize> | null;
	blurOnSubmit?: Accessor<boolean> | null;
	maxLength?: Accessor<number> | null;
	keyboardType?: Accessor<KeyboardType> | null;
	returnKeyType?: Accessor<ReturnKeyType> | null;
	selection?: Accessor<TextSelection> | null;
	onSelectionChange?: ((selection: TextSelection) => void) | null;
	onChangeText?: ((t: string) => void) | null;
	onKeyPress?: ((e: NeonEvent) => void) | null;
	onSubmitEditing?: ((e: NeonEvent) => void) | null;
	onKeyDown?: ((e: NeonEvent) => void) | null;
	onKeyUp?: ((e: NeonEvent) => void) | null;
	onFocus?: ((e: NeonEvent) => void) | null;
	onBlur?: ((e: NeonEvent) => void) | null;
	onLayout?: ((e: NeonEvent) => void) | null;
}

export function TextInput(props: TextInputProps): NeonNode {
	// RN renders a different native view for a multiline input, chosen once.
	const multiline = props.multiline;
	const multilineHost = multiline !== null && untrack((): boolean => (multiline as Accessor<boolean>)());
	const tag = multilineHost ? "multilinetextinput" : "textinput";
	const secureTextEntry = props.secureTextEntry;
	const validateSecureEntry = (): void => {
		if (secureTextEntry !== null && (secureTextEntry as Accessor<boolean>)()
			&& (multilineHost || (multiline !== null && (multiline as Accessor<boolean>)()))) {
			throw new Error("TextInput secureTextEntry is unsupported with multiline");
		}
	};
	const attrs: VAttr[] = [];
	stringAttr(attrs, "value", props.value);
	stringAttr(attrs, "defaultValue", props.defaultValue);
	stringAttr(attrs, "placeholder", props.placeholder);
	stringAttr(attrs, "placeholderTextColor", props.placeholderTextColor);
	flagAttr(attrs, "editable", props.editable);
	flagAttr(attrs, "secureTextEntry", props.secureTextEntry);
	flagAttr(attrs, "multiline", props.multiline);
	for (const a of attrs) {
		if (a.name === "value" || a.name === "defaultValue" || a.name === "secureTextEntry" || a.name === "multiline") {
			const read = a.dyn;
			a.dyn = (): string | null => {
				validateSecureEntry();
				return read();
			};
		}
	}
	flagAttr(attrs, "autoFocus", props.autoFocus);
	flagAttr(attrs, "autoCorrect", props.autoCorrect);
	flagAttr(attrs, "blurOnSubmit", props.blurOnSubmit);
	const capitalize = props.autoCapitalize;
	if (capitalize !== null) {
		const read = capitalize as Accessor<AutoCapitalize>;
		attrs.push(dynAttr("autoCapitalize", (): string | null => { const v: AutoCapitalize = read(); return v; }));
	}
	const maxLength = props.maxLength;
	if (maxLength !== null) { attrs.push(dynAttr("maxLength", (): string | null => Math.round((maxLength as () => number)()).toString())); }
	const keyboard = props.keyboardType;
	if (keyboard !== null) {
		const read = keyboard as Accessor<KeyboardType>;
		attrs.push(dynAttr("keyboardType", (): string | null => { const v: KeyboardType = read(); return v; }));
	}
	const returnKey = props.returnKeyType;
	if (returnKey !== null) {
		const read = returnKey as Accessor<ReturnKeyType>;
		attrs.push(dynAttr("returnKeyType", (): string | null => { const v: ReturnKeyType = read(); return v; }));
	}
	const selection = props.selection;
	if (selection !== null) {
		attrs.push(dynAttr("selection", (): string | null => {
			const sel = (selection as Accessor<TextSelection>)();
			const start = Math.max(0, Math.round(sel.start));
			const end = sel.end === null ? start : Math.max(start, Math.round(sel.end as number));
			return `${start},${end}`;
		}));
	}
	const evts: VEvent[] = interactiveEvents({
		style: null, class: null, onKeyDown: props.onKeyDown, onKeyUp: props.onKeyUp,
		onFocus: null, onBlur: null, onLayout: props.onLayout,
	}, []);
	if (props.onChangeText !== null) {
		const user = props.onChangeText as (t: string) => void;
		evts.push(evt("onChangeText", (e: NeonEvent): void => { user(e.value); }));
	}
	if (props.onSelectionChange !== null) {
		const user = props.onSelectionChange as (selection: TextSelection) => void;
		evts.push(evt("onSelectionChange", (e: NeonEvent): void => { user(selectionOf(e.value)); }));
	}
	if (props.onKeyPress !== null) { evts.push(evt("onKeyPress", props.onKeyPress as (e: NeonEvent) => void)); }
	if (props.onSubmitEditing !== null) { evts.push(evt("onSubmitEditing", props.onSubmitEditing as (e: NeonEvent) => void)); }
	accessibilityEvents(props, evts);
	const userRef = props.ref;
	let focused = false;
	const userFocus = props.onFocus;
	const userBlur = props.onBlur;
	if (userFocus !== null || userRef !== null) {
		evts.push(evt("onFocus", (e: NeonEvent): void => {
			focused = true;
			if (userFocus !== null) { (userFocus as (x: NeonEvent) => void)(e); }
		}));
	}
	if (userBlur !== null || userRef !== null) {
		evts.push(evt("onBlur", (e: NeonEvent): void => {
			focused = false;
			if (userBlur !== null) { (userBlur as (x: NeonEvent) => void)(e); }
		}));
	}
	if (userRef === null) {
		return primitive(tag, { style: props.style, class: props.class }, accessibilityAttrs(props, attrs), evts, null, null);
	}
	let mountedHost: Host | null = null;
	let mounted = false;
	const grab: RefFn = (node: HostNode): void => {
		(userRef as (h: TextInputHandle) => void)(new TextInputHandle(mountedHost as Host, node, (): boolean => focused, (): boolean => mounted));
	};
	const field = primitive(tag, { style: props.style, class: props.class }, accessibilityAttrs(props, attrs), evts, null, grab);
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		mountedHost = host;
		mounted = true;
		onCleanup((): void => { mounted = false; });
		field(host, parent, before);
	};
}

interface VoidProps extends AccessibilityProps {
	style?: Accessor<Style> | null;
	class?: Accessor<string> | null;
	ref?: ((handle: VoidAreaHandle) => void) | null;
	fallback?: NeonNode | null;
	children?: NeonNode | null;
}

export function Void(props: VoidProps): NeonNode {
	const kids = props.children;
	const userRef = props.ref;
	const area: NeonNode = (host: Host, node: HostNode, before: HostNode | null): void => {
		const open = host.voidArea;
		if (open === null) {
			const fallback = props.fallback;
			if (fallback === null) { throw new Error("Void: this host has no Void area (its voidArea is null); give <Void> a fallback to mount where none exists"); }
			(fallback as NeonNode)(host, node, before);
			return;
		}
		const a = (open as (n: HostNode) => VoidArea)(node);
		onCleanup((): void => {
			a.hub.close();
			a.release();
		});
		if (kids !== null) {
			const scoped = getVoidScopeContext().provider({
				value: accessor((): VoidSpace => VoidSpace.Area),
				children: getVoidAreaContext().provider({ value: accessor((): VoidArea | null => a), children: kids as NeonNode }),
			});
			a.hub.enter((): void => { scoped(a.host, a.root, null); });
		}
		if (userRef !== null) { applyRef(a.hub.handle, userRef as (handle: VoidAreaHandle) => void); }
	};
	return primitive("void", { style: props.style, class: props.class, accessible: props.accessible, accessibilityLabel: props.accessibilityLabel, accessibilityHint: props.accessibilityHint, accessibilityRole: props.accessibilityRole, accessibilityState: props.accessibilityState }, [], [], area, null);
}
