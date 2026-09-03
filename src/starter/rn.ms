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
import { NeonNode, VAttr, VEvent, el, attr, evt, dynAttr, withDynStyleAll } from "../render/node";

interface ViewProps {
	style?: () => Style | null;
	class?: string | null;
	children: NeonNode[];
}

export function View(props: ViewProps): NeonNode {
	const kids = props.children;
	const attrs: VAttr[] = [];
	if (props.class !== null) { attrs.push(attr("class", props.class as string)); }
	const n = el("view", attrs, [], kids);
	if (props.style !== null) { withDynStyleAll(n, props.style as () => Style); }
	return n;
}

interface TextProps {
	style?: () => Style | null;
	class?: string | null;
	children: NeonNode[];
}

export function Text(props: TextProps): NeonNode {
	const kids = props.children;
	const attrs: VAttr[] = [];
	if (props.class !== null) { attrs.push(attr("class", props.class as string)); }
	const n = el("text", attrs, [], kids);
	if (props.style !== null) { withDynStyleAll(n, props.style as () => Style); }
	return n;
}

interface PressableProps {
	onPress?: ((e: NeonEvent) => void) | null;
	style?: () => Style | null;
	class?: string | null;
	children: NeonNode[];
}

export function Pressable(props: PressableProps): NeonNode {
	const evts: VEvent[] = [];
	if (props.onPress !== null) {
		evts.push(evt("onPress", props.onPress as (e: NeonEvent) => void));
	}
	const kids = props.children;
	const attrs: VAttr[] = [];
	if (props.class !== null) { attrs.push(attr("class", props.class as string)); }
	const n = el("pressable", attrs, evts, kids);
	if (props.style !== null) { withDynStyleAll(n, props.style as () => Style); }
	return n;
}

interface TextInputProps {
	value?: () => string | null;
	onChangeText?: ((t: string) => void) | null;
	style?: () => Style | null;
	class?: string | null;
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
	return n;
}
