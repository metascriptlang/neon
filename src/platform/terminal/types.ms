// TerminalNode — the host object for terminal rendering.
// Same tree shape as MockNode (browser/dom.ms counterpart); the difference is
// in the paint pass (paint.ms) which walks this tree and emits ANSI lines.

import { NeonEvent } from "../../render/event";

export interface TerminalStyle {
	color: string;
	bg: string;
	bold: boolean;
	dim: boolean;
	italic: boolean;
	underline: boolean;
}

export interface TerminalEvent {
	name: string;
	handler: (e: NeonEvent) => void;
}

export interface TerminalNode {
	tag: string;
	text: string;
	isText: boolean;
	children: TerminalNode[];
	attrs: Map<string, string>;
	events: TerminalEvent[];
	parent: TerminalNode | null;
	style: TerminalStyle;
	dirty: boolean;
}

export function makeStyle(): TerminalStyle {
	return { color: "", bg: "", bold: false, dim: false, italic: false, underline: false };
}

export function createTerminalNode(tag: string): TerminalNode {
	return {
		tag,
		text: "",
		isText: false,
		children: [],
		attrs: new Map<string, string>(),
		events: [],
		parent: null,
		style: makeStyle(),
		dirty: true,
	};
}

export function createTerminalTextNode(s: string): TerminalNode {
	return {
		tag: "",
		text: s,
		isText: true,
		children: [],
		attrs: new Map<string, string>(),
		events: [],
		parent: null,
		style: makeStyle(),
		dirty: true,
	};
}
