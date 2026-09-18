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
import { Style } from "../render/style";
import { onCleanup } from "../core/cleanup";
import { Accessor, accessor } from "../core/signal";
import { NeonNode, VAttr, VEvent, RefFn, hostElement, attr, evt, dynAttr } from "../render/node";

interface HostProps {
	style?: Accessor<Style> | null;
	class?: Accessor<string> | null;
	ref?: RefFn | null;
}

function primitive(tag: string, props: HostProps, attrs: VAttr[], evts: VEvent[], kids: NeonNode[]): NeonNode {
	if (props.class !== null) { attrs.push(attr("class", props.class as string)); }
	let style: (() => Style) | null = null;
	if (props.style !== null) { style = props.style as () => Style; }
	return hostElement(tag, attrs, evts, kids, style, props.ref);
}

interface ViewProps extends HostProps {
	children: NeonNode[];
}

export function View(props: ViewProps): NeonNode {
	return primitive("view", props, [], [], props.children);
}

interface TextProps extends HostProps {
	children: NeonNode[];
}

export function Text(props: TextProps): NeonNode {
	return primitive("text", props, [], [], props.children);
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
	children: NeonNode[];
}

// Two tiers, chosen once at build time from the props the caller actually
// declared. `onPress` alone stays ONE click listener — the common button pays
// nothing for gestures it never asked for. Declaring any of pressIn/pressOut/
// longPress opts into the state machine, which then OWNS the press: it tracks
// pointer down/up/leave itself, because "did this press become a long press"
// is not a question the host's click event can answer.
export function Pressable(props: PressableProps): NeonNode {
	const evts: VEvent[] = [];
	const { onPress, onPressIn, onPressOut, onLongPress, delayLongPress = accessor(() => LONG_PRESS_DELAY_MS) } = props;
	const wantsGestures = onPressIn !== null || onPressOut !== null || onLongPress !== null;

	let state = 0;           // 0 idle · 1 pressing · 2 long-pressing
	let longId = -1;
	let minId = -1;
	let minHeld = false;
	let outPending: NeonEvent | null = null;

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
		evts.push(evt("onPointerDown", down));
		evts.push(evt("onPointerUp", up));
		evts.push(evt("onPointerLeave", leave));
		evts.push(evt("onPointerCancel", leave));
		onCleanup((): void => {
			cancelTimer(longId);
			cancelTimer(minId);
		});
	} else if (onPress !== null) {
		evts.push(evt("onPress", onPress as (e: NeonEvent) => void));
	}

	return primitive("pressable", props, [], evts, props.children);
}

interface TextInputProps extends HostProps {
	value?: Accessor<string> | null;
	onChangeText?: ((t: string) => void) | null;
}

export function TextInput(props: TextInputProps): NeonNode {
	const attrs: VAttr[] = [];
	if (props.value !== null) {
		const value = props.value as () => string;
		attrs.push(dynAttr("value", () => value()));
	}
	const evts: VEvent[] = [];
	if (props.onChangeText !== null) {
		const user = props.onChangeText as (t: string) => void;
		evts.push(evt("onChangeText", (e: NeonEvent): void => { user(e.value); }));
	}
	return primitive("textinput", props, attrs, evts, []);
}
