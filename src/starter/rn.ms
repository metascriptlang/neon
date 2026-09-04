// The universal component vocabulary (user decision 2026-09-03): users write
// View/Text/TextInput/Pressable — RN-shaped, mobile-first; div/span are HTML
// details no user should meet. These are real components (the createComponent
// seam, so bodies run once at mount): each renders the LOWERCASE wire tag and
// every host translates that tag in its own createElement (browser:
// htmlTagFor; terminal: box; void ignores tags; mock records as written).
//
// Prop contract (component.test pins it): CALL expression props arrive as
// THUNKS (style is () => Style → withDynStyleAll, the call-based law's
// channel), while arrow literals cross RAW and take the field's flat type
// (handlers declare (e: NeonEvent) => void directly). `class` is the RN-web
// escape hatch: a string literal attr crosses as a plain string, honored by
// the browser host's CSS-class channel, ignored by native. children: NeonNode[] keeps children tree-emitted so
// SSR still serializes them (RENDER-MODEL §Selection — component bodies stay
// tree); a view-children channel is a measured follow-up if the js lane ever
// needs direct-emitted children inside these containers.
//
// `onChangeText` stays RN-shaped here at RUNTIME — the component wraps the
// user's (text) => void around the host's (e: NeonEvent) => void contract, no
// macro machinery involved (the macro-side wrap in element/direct covers the
// same name on raw lowercase tags).

import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { onCleanup } from "../core/cleanup";
import { NeonNode, VAttr, VEvent, RefFn, el, attr, evt, dynAttr, withDynStyleAll, withRef } from "../render/node";

interface ViewProps {
	style?: () => Style | null;
	class?: string | null;
	ref?: RefFn | null;
	children: NeonNode[];
}

export function View(props: ViewProps): NeonNode {
	const kids = props.children;
	const attrs: VAttr[] = [];
	if (props.class !== null) { attrs.push(attr("class", props.class as string)); }
	const n = el("view", attrs, [], kids);
	if (props.style !== null) { withDynStyleAll(n, props.style as () => Style); }
	if (props.ref !== null) { withRef(n, props.ref as RefFn); }
	return n;
}

interface TextProps {
	style?: () => Style | null;
	class?: string | null;
	ref?: RefFn | null;
	children: NeonNode[];
}

export function Text(props: TextProps): NeonNode {
	const kids = props.children;
	const attrs: VAttr[] = [];
	if (props.class !== null) { attrs.push(attr("class", props.class as string)); }
	const n = el("text", attrs, [], kids);
	if (props.style !== null) { withDynStyleAll(n, props.style as () => Style); }
	if (props.ref !== null) { withRef(n, props.ref as RefFn); }
	return n;
}

// RN Pressability's two constants (Libraries/Pressability/Pressability.js):
// a press becomes a LONG press at 500ms, and a press stays visibly held for at
// least 130ms so a fast tap still shows feedback instead of flickering.
const LONG_PRESS_DELAY_MS = 500;
const MIN_PRESS_DURATION_MS = 130;

interface PressableProps {
	onPress?: ((e: NeonEvent) => void) | null;
	onPressIn?: ((e: NeonEvent) => void) | null;
	onPressOut?: ((e: NeonEvent) => void) | null;
	onLongPress?: ((e: NeonEvent) => void) | null;
	delayLongPress?: number | null;
	style?: () => Style | null;
	class?: string | null;
	ref?: RefFn | null;
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
	const onPress = props.onPress;
	const onPressIn = props.onPressIn;
	const onPressOut = props.onPressOut;
	const onLongPress = props.onLongPress;
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
				const d = props.delayLongPress;
				const delay = d === null ? LONG_PRESS_DELAY_MS : (d as number);
				longId = setTimeout((): void => {
					if (state !== 1) { return; }
					state = 2;
					(onLongPress as (x: NeonEvent) => void)(e);
				}, delay) as int32;
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

	const kids = props.children;
	const attrs: VAttr[] = [];
	if (props.class !== null) { attrs.push(attr("class", props.class as string)); }
	const n = el("pressable", attrs, evts, kids);
	if (props.style !== null) { withDynStyleAll(n, props.style as () => Style); }
	if (props.ref !== null) { withRef(n, props.ref as RefFn); }
	return n;
}

interface TextInputProps {
	value?: () => string | null;
	onChangeText?: ((t: string) => void) | null;
	style?: () => Style | null;
	class?: string | null;
	ref?: RefFn | null;
}

export function TextInput(props: TextInputProps): NeonNode {
	const attrs: VAttr[] = [];
	if (props.value !== null) {
		attrs.push(dynAttr("value", props.value as () => string));
	}
	const evts: VEvent[] = [];
	if (props.onChangeText !== null) {
		const user = props.onChangeText as (t: string) => void;
		evts.push(evt("onChangeText", (e: NeonEvent): void => { user(e.value); }));
	}
	if (props.class !== null) { attrs.push(attr("class", props.class as string)); }
	const n = el("textinput", attrs, evts, []);
	if (props.style !== null) { withDynStyleAll(n, props.style as () => Style); }
	if (props.ref !== null) { withRef(n, props.ref as RefFn); }
	return n;
}
