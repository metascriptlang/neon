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

interface HostProps {
	style?: Accessor<Style> | null;
	class?: Accessor<string> | null;
	ref?: RefFn | null;
}

function primitive(tag: string, props: HostProps, attrs: VAttr[], evts: VEvent[], kids: NeonNode | null): NeonNode {
	if (props.class !== null) {
		const cls = props.class as () => string;
		attrs.push(dynAttr("class", () => cls()));
	}
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

export function Text(props: TextProps): NeonNode {
	return element(<text class={props.class} style={props.style} ref={props.ref}>{props.children}</text>);
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

	return element(<pressable class={props.class} style={props.style} ref={props.ref} onPress={press} onPointerDown={pointerDown} onPointerUp={pointerUp} onPointerLeave={pointerLeave} onPointerCancel={pointerLeave}>{props.children}</pressable>);
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
	const inner: NeonNode = (host: Host, node: HostNode, before: HostNode | null): void => {
		content(host, node, before);
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

interface TextInputProps extends InteractiveProps {
	value?: Accessor<string> | null;
	onChangeText?: ((t: string) => void) | null;
	onKeyPress?: ((e: NeonEvent) => void) | null;
	onSubmitEditing?: ((e: NeonEvent) => void) | null;
}

export function TextInput(props: TextInputProps): NeonNode {
	const attrs: VAttr[] = [];
	if (props.value !== null) {
		const value = props.value as () => string;
		attrs.push(dynAttr("value", () => value()));
	}
	const evts: VEvent[] = interactiveEvents(props, []);
	if (props.onChangeText !== null) {
		const user = props.onChangeText as (t: string) => void;
		evts.push(evt("onChangeText", (e: NeonEvent): void => { user(e.value); }));
	}
	if (props.onKeyPress !== null) { evts.push(evt("onKeyPress", props.onKeyPress as (e: NeonEvent) => void)); }
	if (props.onSubmitEditing !== null) { evts.push(evt("onSubmitEditing", props.onSubmitEditing as (e: NeonEvent) => void)); }
	return primitive("textinput", props, attrs, evts, null);
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
