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
import { Accessor, accessor } from "../core/signal";
import { element } from "../macros/ui/element";
import { NeonNode, VAttr, VEvent, RefFn, hostElement, evt, dynAttr } from "../render/node";
import { Host, HostNode, VoidArea } from "../render/hostTypes";
import { visibleContentAttr } from "../render/visibleContent";

export type AccessibilityRole = "none" | "button" | "link" | "search" | "image" | "text" | "header" | "switch" | "checkbox" | "adjustable" | "progressbar" | "summary" | "alert";

export interface AccessibilityProps {
	accessible?: Accessor<boolean> | null;
	accessibilityLabel?: Accessor<string> | null;
	accessibilityHint?: Accessor<string> | null;
	accessibilityRole?: Accessor<AccessibilityRole> | null;
}

interface HostProps extends AccessibilityProps {
	style?: Accessor<Style> | null;
	class?: Accessor<string> | null;
	ref?: RefFn | null;
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

export function accessibilityAttrs(props: AccessibilityProps, attrs: VAttr[]): VAttr[] {
	flagAttr(attrs, "accessible", props.accessible);
	stringAttr(attrs, "accessibilityLabel", props.accessibilityLabel);
	stringAttr(attrs, "accessibilityHint", props.accessibilityHint);
	const role = props.accessibilityRole;
	if (role !== null) {
		const read = role as Accessor<AccessibilityRole>;
		attrs.push(dynAttr("accessibilityRole", (): string | null => { const v: AccessibilityRole = read(); return v; }));
	}
	return attrs;
}

function primitive(tag: string, props: HostProps, attrs: VAttr[], evts: VEvent[], kids: NeonNode | null): NeonNode {
	if (props.class !== null) {
		const cls = props.class as () => string;
		attrs.push(dynAttr("class", () => cls()));
	}
	accessibilityAttrs(props, attrs);
	let style: (() => Style) | null = null;
	if (props.style !== null) { style = props.style as () => Style; }
	return hostElement(tag, attrs, evts, kids, style, props.ref);
}

interface InteractiveProps extends HostProps {
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
	return evts;
}

interface ViewProps extends InteractiveProps {
	children?: NeonNode | null;
}

export function View(props: ViewProps): NeonNode {
	return primitive("view", props, [], interactiveEvents(props, []), props.children);
}

interface TextProps extends HostProps {
	children?: NeonNode | null;
}

function accessibleText(props: AccessibilityProps): Accessor<string> | null {
	const flag = props.accessible;
	if (flag === null) { return null; }
	const read = flag as Accessor<boolean>;
	return accessor((): string => read() ? "true" : "false");
}

export function Text(props: TextProps): NeonNode {
	const accessible = accessibleText(props);
	return element(<text class={props.class} style={props.style} ref={props.ref} accessible={accessible} accessibilityLabel={props.accessibilityLabel} accessibilityHint={props.accessibilityHint} accessibilityRole={props.accessibilityRole}>{props.children}</text>);
}

// RN Pressability's two constants (Libraries/Pressability/Pressability.js):
// a press becomes a LONG press at 500ms, and a press stays visibly held for at
// least 130ms so a fast tap still shows feedback instead of flickering.
const LONG_PRESS_DELAY_MS = 500;
const MIN_PRESS_DURATION_MS = 130;

interface PressableProps extends HostProps {
	onPress?: ((e: NeonEvent) => void) | null;
	onPressIn?: ((e: NeonEvent) => void) | null;
	onPressOut?: ((e: NeonEvent) => void) | null;
	onLongPress?: ((e: NeonEvent) => void) | null;
	onLayout?: ((e: NeonEvent) => void) | null;
	delayLongPress?: Accessor<number> | null;
	children?: NeonNode | null;
}

// Two tiers, chosen once at build time from the props the caller actually
// declared. `onPress` alone stays ONE click listener — the common button pays
// nothing for gestures it never asked for. Declaring any of pressIn/pressOut/
// longPress opts into the state machine, which then OWNS the press: it tracks
// pointer down/up/leave itself, because "did this press become a long press"
// is not a question the host's click event can answer.
export function Pressable(props: PressableProps): NeonNode {
	const { onPress, onPressIn, onPressOut, onLongPress, delayLongPress = accessor(() => LONG_PRESS_DELAY_MS) } = props;
	const wantsGestures = onPressIn !== null || onPressOut !== null || onLongPress !== null;

	let state = 0;           // 0 idle · 1 pressing · 2 long-pressing
	let longId = -1;
	let minId = -1;
	let minHeld = false;
	let outPending: NeonEvent | null = null;

	let press: ((e: NeonEvent) => void) | null = null;
	let pointerDown: ((e: NeonEvent) => void) | null = null;
	let pointerUp: ((e: NeonEvent) => void) | null = null;
	let pointerLeave: ((e: NeonEvent) => void) | null = null;

	if (wantsGestures) {
		const cancelTimer = (id: number): void => {
			if (id >= 0) { clearTimeout(id); }
		};
		const fireOut = (e: NeonEvent): void => {
			if (onPressOut !== null) { (onPressOut as (x: NeonEvent) => void)(e); }
		};
		// RN _deactivate: pressOut waits out the remainder of the minimum hold,
		// so a 10ms tap still shows ~130ms of pressed state.
		const releaseOut = (e: NeonEvent): void => {
			if (minHeld) { fireOut(e); } else { outPending = e; }
		};
		const down = (e: NeonEvent): void => {
			if (state !== 0) { return; }
			state = 1;
			minHeld = false;
			outPending = null;
			if (onPressIn !== null) { (onPressIn as (x: NeonEvent) => void)(e); }
			minId = setTimeout((): void => {
				minHeld = true;
				const held = outPending;
				if (held !== null) {
					outPending = null;
					fireOut(held as NeonEvent);
				}
			}, MIN_PRESS_DURATION_MS) as int32;
			if (onLongPress !== null) {
				longId = setTimeout((): void => {
					if (state !== 1) { return; }
					state = 2;
					(onLongPress as (x: NeonEvent) => void)(e);
				}, delayLongPress) as int32;
			}
		};
		// RN: `isPressCanceledByLongPress` — a press that already fired
		// onLongPress does NOT also fire onPress, so a context menu and the
		// primary action never both run off one gesture.
		const up = (e: NeonEvent): void => {
			if (state === 0) { return; }
			const wasLong = state === 2;
			cancelTimer(longId);
			longId = -1;
			state = 0;
			releaseOut(e);
			if (wasLong && onLongPress !== null) { return; }
			if (onPress !== null) { (onPress as (x: NeonEvent) => void)(e); }
		};
		// Leaving the element (or the host cancelling) ends the press WITHOUT
		// firing onPress — RN's press-rect exit, minus the rect measurement.
		const leave = (e: NeonEvent): void => {
			if (state === 0) { return; }
			cancelTimer(longId);
			longId = -1;
			state = 0;
			releaseOut(e);
		};
		pointerDown = down;
		pointerUp = up;
		pointerLeave = leave;
		onCleanup((): void => {
			cancelTimer(longId);
			cancelTimer(minId);
		});
	} else {
		press = onPress;
	}

	// RN Pressable.js: `accessible: accessible !== false`, so a Pressable is one
	// accessibility element whose label the host composes from its texts.
	const declared = accessibleText(props);
	const accessible = declared === null ? accessor((): string => "true") : declared as Accessor<string>;
	return element(<pressable class={props.class} style={props.style} ref={props.ref} accessible={accessible} accessibilityLabel={props.accessibilityLabel} accessibilityHint={props.accessibilityHint} accessibilityRole={props.accessibilityRole} onLayout={props.onLayout} onPress={press} onPointerDown={pointerDown} onPointerUp={pointerUp} onPointerLeave={pointerLeave} onPointerCancel={pointerLeave}>{props.children}</pressable>);
}

export interface ScrollToOptions {
	x?: number | null;
	y?: number | null;
	animated?: boolean | null;
}

export class ScrollViewHandle {
	node: HostNode;
	private host: Host;
	private mounted: () => boolean;

	constructor(host: Host, node: HostNode, mounted: () => boolean) {
		this.host = host;
		this.node = node;
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

interface ScrollViewProps {
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
	if (props.onScroll !== null) {
		const user = props.onScroll as (e: NeonEvent) => void;
		const throttle = props.scrollEventThrottle;
		let last = -1.0;
		evts.push(evt("onScroll", (e: NeonEvent): void => {
			const every = throttle === null ? 0 : (throttle as () => number)();
			if (every > EVERY_FRAME_MS) {
				const now = performance.now();
				if (last >= 0 && now - last < every) { return; }
				last = now;
			}
			user(e);
		}));
	}
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
	const inner: NeonNode = (host: Host, node: HostNode, before: HostNode | null): void => {
		content(host, node, before);
		if (refreshControl !== null) { (refreshControl as NeonNode)(host, node, null); }
		if (userRef !== null) {
			let mounted = true;
			onCleanup((): void => { mounted = false; });
			(userRef as (h: ScrollViewHandle) => void)(new ScrollViewHandle(host, node, (): boolean => mounted));
		}
	};
	const userStyle = props.style;
	const style: Accessor<Style> = accessor((): Style => {
		const base = horizontal !== null && (horizontal as () => boolean)() ? SCROLL_HORIZONTAL : SCROLL_BASE;
		return userStyle === null ? base : layerStyles([base, (userStyle as () => Style)()]);
	});
	return primitive("scrollview", { style, class: props.class, ref: null }, attrs, evts, inner);
}

export type KeyboardType = "default" | "numeric" | "number-pad" | "decimal-pad" | "email-address" | "phone-pad" | "url";
export type ReturnKeyType = "done" | "go" | "next" | "search" | "send";
export type AutoCapitalize = "none" | "sentences" | "words" | "characters";

export class TextInputHandle {
	node: HostNode;
	private host: Host;
	private focused: () => boolean;
	private mounted: () => boolean;

	constructor(host: Host, node: HostNode, focused: () => boolean, mounted: () => boolean) {
		this.host = host;
		this.node = node;
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
	const attrs: VAttr[] = [];
	stringAttr(attrs, "value", props.value);
	stringAttr(attrs, "defaultValue", props.defaultValue);
	stringAttr(attrs, "placeholder", props.placeholder);
	stringAttr(attrs, "placeholderTextColor", props.placeholderTextColor);
	flagAttr(attrs, "editable", props.editable);
	flagAttr(attrs, "secureTextEntry", props.secureTextEntry);
	flagAttr(attrs, "multiline", props.multiline);
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
	const evts: VEvent[] = interactiveEvents({
		style: null, class: null, ref: null, onKeyDown: props.onKeyDown, onKeyUp: props.onKeyUp,
		onFocus: null, onBlur: null, onLayout: props.onLayout,
	}, []);
	if (props.onChangeText !== null) {
		const user = props.onChangeText as (t: string) => void;
		evts.push(evt("onChangeText", (e: NeonEvent): void => { user(e.value); }));
	}
	if (props.onKeyPress !== null) { evts.push(evt("onKeyPress", props.onKeyPress as (e: NeonEvent) => void)); }
	if (props.onSubmitEditing !== null) { evts.push(evt("onSubmitEditing", props.onSubmitEditing as (e: NeonEvent) => void)); }
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
		return primitive("textinput", { style: props.style, class: props.class, ref: null }, accessibilityAttrs(props, attrs), evts, null);
	}
	let mountedHost: Host | null = null;
	let mounted = false;
	const grab: RefFn = (node: HostNode): void => {
		(userRef as (h: TextInputHandle) => void)(new TextInputHandle(mountedHost as Host, node, (): boolean => focused, (): boolean => mounted));
	};
	const field = primitive("textinput", { style: props.style, class: props.class, ref: grab }, accessibilityAttrs(props, attrs), evts, null);
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		mountedHost = host;
		mounted = true;
		onCleanup((): void => { mounted = false; });
		field(host, parent, before);
	};
}

interface VoidProps extends HostProps {
	children?: NeonNode | null;
}

export function Void(props: VoidProps): NeonNode {
	const kids = props.children;
	const area: NeonNode = (host: Host, node: HostNode, before: HostNode | null): void => {
		const open = host.voidArea;
		if (open === null) { throw "<Void> needs a host with the voidArea capability, and this host has none"; }
		const a = (open as (n: HostNode) => VoidArea)(node);
		onCleanup((): void => { a.release(); });
		if (kids !== null) { (kids as NeonNode)(a.host, a.root, null); }
	};
	return primitive("void", props, [], [], area);
}
