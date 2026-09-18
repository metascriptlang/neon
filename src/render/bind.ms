import { createEffect } from "../core/effect";
import { Style, StyleValue, setStyleField } from "./style";
import { Host, HostNode, RefFn } from "./hostTypes";

// A dynamic spot re-runs whenever a source signal changes, but a derived expression
// often maps several source values onto the SAME output ("big"/"small", a formatted
// count). Writing it again is a host touch that changes nothing, so the last written
// value is kept and an identical one is dropped.
export function bindText(host: Host, node: HostNode, get: () => string): void {
	let prev = "";
	let bound = false;
	createEffect(() => {
		const v = get();
		if (bound && v === prev) { return; }
		bound = true;
		prev = v;
		host.setText(node, v);
	});
}

export function writeAttr(host: Host, node: HostNode, name: string, value: string | null): void {
	if (value === null) {
		host.removeAttr(node, name);
	} else {
		host.setAttr(node, name, value as string);
	}
}

export function bindAttr(host: Host, node: HostNode, name: string, get: () => string | null): void {
	let prev: string | null = null;
	let bound = false;
	createEffect(() => {
		const v = get();
		if (bound && v === prev) { return; }
		bound = true;
		prev = v;
		writeAttr(host, node, name, v);
	});
}

export function bindStyleProp(host: Host, node: HostNode, own: Style, name: string, get: () => StyleValue): void {
	let prev: StyleValue = null;
	let bound = false;
	createEffect(() => {
		const v = get();
		if (bound && v === prev) { return; }
		bound = true;
		prev = v;
		const setProp = host.setStyleProp;
		if (setProp !== null) { setProp(node, name, v); return; }
		setStyleField(own, name, v);
		host.setStyle(node, own);
	});
}

export function applyStaticStyle(host: Host, node: HostNode, s: Style): void {
	const setCls = host.setStyleClass;
	const id = s.cssId;
	if (id !== null && setCls !== null) {
		setCls(node, id as string, s.css === null ? "" : s.css as string);
	} else { host.setStyle(node, s); }
}

// One effect re-applying the whole style (reactive variant selection, layered
// calls — any style EXPRESSION that reads a signal). Per-property precision is
// impossible here: which fields the result carries is only known per run, and
// a field can fall back to an earlier layer when deselected, so the effect
// hands the fresh merge to setStyle each time.
export function bindStyleAll(host: Host, node: HostNode, get: () => Style): void {
	createEffect(() => {
		host.setStyle(node, get());
	});
}

export function applyRef(node: HostNode, fn: RefFn): void {
	fn(node);
}
