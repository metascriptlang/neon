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

export function makeStyle(): TerminalStyle {
	return { color: "", bg: "", bold: false, dim: false, italic: false, underline: false };
}

export class TerminalNode {
	tag: string;
	text: string = "";
	isText: boolean = false;
	children: TerminalNode[] = [];
	attrs: Map<string, string>;
	events: TerminalEvent[] = [];
	parent: TerminalNode | null = null;
	style: TerminalStyle;
	dirty: boolean = true;

	constructor(tag: string) {
		this.tag = tag;
		this.attrs = new Map<string, string>();
		this.style = makeStyle();
	}
}

export function createTerminalNode(tag: string): TerminalNode {
	return new TerminalNode(tag);
}

export function createTerminalTextNode(s: string): TerminalNode {
	const n = new TerminalNode("");
	n.text = s;
	n.isText = true;
	return n;
}
