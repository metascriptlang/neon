import { createBindingEffect } from "../core/effect";
import { untrack } from "../core/signal";
import { getOwner } from "../core/runtime";
import { Style, StyleValue, setStyleField, emptyStyle } from "./style";
import { Host, HostNode } from "./hostTypes";
import { isServer } from "./environment";

// A dynamic spot re-runs whenever a source signal changes, but a derived expression
// often maps several source values onto the SAME output ("big"/"small", a formatted
// count). Writing it again is a host touch that changes nothing, so the last written
// value is kept and an identical one is dropped.
export function bindText(host: Host, node: HostNode, get: () => string): void {
	if (isServer()) { host.setText(node, untrack(get)); return; }
	followText(host, node, get);
}

function followText(host: Host, node: HostNode, get: () => string): void {
	let prev = "";
	let bound = false;
	createBindingEffect(() => {
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
	if (isServer()) { writeAttr(host, node, name, untrack(get)); return; }
	followAttr(host, node, name, get);
}

function followAttr(host: Host, node: HostNode, name: string, get: () => string | null): void {
	let prev: string | null = null;
	let bound = false;
	createBindingEffect(() => {
		const v = get();
		if (bound && v === prev) { return; }
		bound = true;
		prev = v;
		writeAttr(host, node, name, v);
	});
}

function writeStyleProp(host: Host, node: HostNode, own: Style, name: string, v: StyleValue): void {
	const setProp = host.setStyleProp;
	if (setProp !== null) { setProp(node, name, v); return; }
	setStyleField(own, name, v);
	host.setStyle(node, own);
}

export function bindStyleProp(host: Host, node: HostNode, own: Style, name: string, get: () => StyleValue): void {
	if (isServer()) { writeStyleProp(host, node, own, name, untrack(get)); return; }
	followStyleProp(host, node, own, name, get);
}

function followStyleProp(host: Host, node: HostNode, own: Style, name: string, get: () => StyleValue): void {
	let prev: StyleValue = null;
	let bound = false;
	createBindingEffect(() => {
		const v = get();
		if (bound && v === prev) { return; }
		bound = true;
		prev = v;
		writeStyleProp(host, node, own, name, v);
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
// hands the fresh merge to setStyle each time. A sheet entry on a host with a
// stylesheet goes through its class instead, so a rule the inline style would
// outrank (a breakpoint's) still applies; switching between the two channels
// clears the one left behind.
export function bindStyleAll(host: Host, node: HostNode, get: () => Style): void {
	if (isServer()) { applyStaticStyle(host, node, untrack(get)); return; }
	followStyleAll(host, node, get);
}

function followStyleAll(host: Host, node: HostNode, get: () => Style): void {
	const setCls = host.setStyleClass;
	let classed = false;
	let inlined = false;
	createBindingEffect(() => {
		const s = get();
		const id = s.cssId;
		if (id !== null && setCls !== null) {
			if (inlined) { host.setStyle(node, emptyStyle()); inlined = false; }
			setCls(node, id as string, s.css === null ? "" : s.css as string);
			classed = true;
			return;
		}
		if (classed && setCls !== null) { setCls(node, "", ""); classed = false; }
		host.setStyle(node, s);
		inlined = true;
	});
}

export function setupRef<T>(setup: () => T): T {
	if (getOwner() === null) {
		throw "a ref directive factory ran with no owner, so its onCleanup and effects would never be disposed: mount the element inside render() or a component";
	}
	return untrack(setup);
}

export function applyRef<T>(target: T, fn: (target: T) => void): void {
	if (isServer()) { return; }
	untrack((): void => { fn(target); });
}

export function composeRefs<T>(fns: (((target: T) => void) | null)[]): (target: T) => void {
	return (target: T): void => {
		for (const fn of fns) {
			if (fn !== null) { (fn as (target: T) => void)(target); }
		}
	};
}
