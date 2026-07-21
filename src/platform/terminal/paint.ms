// Terminal paint — walks a TerminalNode tree and produces string[] (one per line).
//
// Layout model:
//   <box flexDirection="column">  → children stacked vertically (default)
//   <box flexDirection="row">     → children side by side horizontally
//   <text>                        → text content, word-wrapped to width
//   <hr>                          → horizontal rule filling width
//   <gap height="N">              → N blank lines
//
// Box attrs: border ("true"), padding (number), color, bg
// Text attrs: color, bold, dim, italic, underline
//
// This is the terminal equivalent of the browser engine's layout + paint pass.
// Called after renderToHost builds the TerminalNode tree, and again on every
// reactive update (dirty nodes).

import { TerminalNode, TerminalStyle } from "./types";

// ANSI SGR codes
const RESET = "\x1b[0m";
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";
const ITALIC = "\x1b[3m";
const UNDERLINE = "\x1b[4m";

function ansiColor(prefix: string, name: string): string {
	if (name === "") { return ""; }
	const codes: Map<string, string> = new Map<string, string>();
	codes.set("black", prefix === "fg" ? "30" : "40");
	codes.set("red", prefix === "fg" ? "31" : "41");
	codes.set("green", prefix === "fg" ? "32" : "42");
	codes.set("yellow", prefix === "fg" ? "33" : "43");
	codes.set("blue", prefix === "fg" ? "34" : "44");
	codes.set("magenta", prefix === "fg" ? "35" : "45");
	codes.set("cyan", prefix === "fg" ? "36" : "46");
	codes.set("white", prefix === "fg" ? "37" : "47");
	codes.set("gray", prefix === "fg" ? "90" : "100");
	codes.set("bright-red", prefix === "fg" ? "91" : "101");
	codes.set("bright-green", prefix === "fg" ? "92" : "102");
	codes.set("bright-yellow", prefix === "fg" ? "93" : "103");
	codes.set("bright-blue", prefix === "fg" ? "94" : "104");
	codes.set("bright-magenta", prefix === "fg" ? "95" : "105");
	codes.set("bright-cyan", prefix === "fg" ? "96" : "106");
	const code = codes.get(name);
	if (code === null) { return ""; }
	return "\x1b[" + code + "m";
}

function stylePrefix(s: TerminalStyle): string {
	let p = "";
	if (s.bold) { p = p + BOLD; }
	if (s.dim) { p = p + DIM; }
	if (s.italic) { p = p + ITALIC; }
	if (s.underline) { p = p + UNDERLINE; }
	if (s.color !== "") { p = p + ansiColor("fg", s.color); }
	if (s.bg !== "") { p = p + ansiColor("bg", s.bg); }
	return p;
}

function pad2(n: number): string {
	if (n < 10) { return " " + n.toString(); }
	return n.toString();
}

// Word-wrap a string to a given width. Returns array of lines (no ANSI).
function wrapText(s: string, width: number): string[] {
	if (width <= 0) { return [""]; }
	const words = s.split(" ");
	const lines: string[] = [];
	let current = "";
	for (const word of words) {
		if (current === "") {
			current = word;
		} else if (current.length + 1 + word.length <= width) {
			current = current + " " + word;
		} else {
			lines.push(current);
			current = word;
		}
	}
	if (current !== "" || lines.length === 0) {
		lines.push(current);
	}
	return lines;
}

// Split text on explicit newlines, then word-wrap each segment.
function splitLines(s: string, width: number): string[] {
	const result: string[] = [];
	const segments = s.split("\n");
	for (const seg of segments) {
		const wrapped = wrapText(seg, width);
		for (const w of wrapped) {
			result.push(w);
		}
	}
	return result;
}

// Apply ANSI style to a line and pad/truncate to exact width.
function styleLine(content: string, width: number, s: TerminalStyle, pad: boolean): string {
	const prefix = stylePrefix(s);
	const visibleLen = content.length;
	let body = content;
	if (pad && visibleLen < width) {
		body = content + " ".repeat(width - visibleLen);
	} else if (visibleLen > width) {
		body = content.slice(0, width);
	}
	if (prefix === "") { return body; }
	return prefix + body + RESET;
}

function getAttr(node: TerminalNode, name: string, fallback: string): string {
	if (!node.attrs.has(name)) { return fallback; }
	const v = node.attrs.get(name);
	if (v === null) { return fallback; }
	return v;
}

function getAttrNum(node: TerminalNode, name: string, fallback: number): number {
	if (!node.attrs.has(name)) { return fallback; }
	const v = node.attrs.get(name);
	if (v === null) { return fallback; }
	return parseInt(v);
}

// Paint a single node into a list of styled lines fitting within `width`.
export function paintNode(node: TerminalNode, width: number): string[] {
	if (node.isText) {
		const lines = splitLines(node.text, width);
		const result: string[] = [];
		for (const line of lines) {
			result.push(styleLine(line, width, node.style, false));
		}
		return result;
	}

	match (node.tag) {
		"text" => {
			const lines = splitLines(node.text, width);
			const result: string[] = [];
			for (const line of lines) {
				result.push(styleLine(line, width, node.style, false));
			}
			return result;
		},
		"span" => {
			return [styleLine(node.text, width, node.style, false)];
		},
		"hr" => {
			return [styleLine("─".repeat(width), width, node.style, false)];
		},
		"gap" => {
			const h = getAttrNum(node, "height", 1);
			const result: string[] = [];
			let i = 0;
			while (i < h) { result.push(""); i += 1; }
			return result;
		},
		_ => {},
	};

	// Default: container (box, row, custom tags)
	const hasBorder = getAttr(node, "border", "false") === "true";
	const padding = getAttrNum(node, "padding", 0);
	let dirDefault = "column";
	if (node.tag === "row") { dirDefault = "row"; }
	const flexDirection = getAttr(node, "flexDirection", dirDefault);

	const innerWidth = width - (hasBorder ? 2 : 0) - padding * 2;

	if (flexDirection === "row") {
		return paintRow(node, innerWidth, hasBorder, padding);
	}
	return paintColumn(node, innerWidth, hasBorder, padding);
}

function paintColumn(node: TerminalNode, innerWidth: number, hasBorder: boolean, padding: number): string[] {
	const lines: string[] = [];

	for (const child of node.children) {
		const childLines = paintNode(child, innerWidth);
		for (const line of childLines) {
			lines.push(line);
		}
	}

	return applyBoxDecoration(lines, node, innerWidth, hasBorder, padding);
}

function paintRow(node: TerminalNode, innerWidth: number, hasBorder: boolean, padding: number): string[] {
	if (node.children.length === 0) {
		return applyBoxDecoration([], node, innerWidth, hasBorder, padding);
	}

	const childWidth = (innerWidth / node.children.length) as int32;
	const blocks: string[][] = [];
	let maxLines = 0;
	for (const child of node.children) {
		const childLines = paintNode(child, childWidth);
		blocks.push(childLines);
		if (childLines.length > maxLines) { maxLines = childLines.length; }
	}

	const lines: string[] = [];
	let row = 0;
	while (row < maxLines) {
		let line = "";
		let bi = 0;
		while (bi < blocks.length) {
			const block = blocks[bi];
			if (row < block.length) {
				line = line + block[row];
				const padLen = childWidth - visibleLen(block[row]);
				if (padLen > 0) { line = line + " ".repeat(padLen); }
			} else {
				line = line + " ".repeat(childWidth);
			}
			bi += 1;
		}
		lines.push(line);
		row += 1;
	}

	return applyBoxDecoration(lines, node, innerWidth, hasBorder, padding);
}

function visibleLen(s: string): number {
	let len = 0;
	let inEscape = false;
	let i = 0;
	while (i < s.length) {
		const code = s.charCodeAt(i);
		if (code === 0x1b) { inEscape = true; i += 1; continue; }
		if (inEscape) {
			if (code === "m".code) { inEscape = false; }
			i += 1;
			continue;
		}
		len += 1;
		i += 1;
	}
	return len;
}

function applyBoxDecoration(
	lines: string[], node: TerminalNode, innerWidth: number, hasBorder: boolean, padding: number
): string[] {
	let working = lines;

	if (padding > 0) {
		const padLine = " ".repeat(innerWidth);
		const padded: string[] = [];
		let pi = 0;
		while (pi < padding) { padded.push(padLine); pi += 1; }
		for (const line of working) {
			let content = line;
			const vl = visibleLen(line);
			if (vl < innerWidth) { content = line + " ".repeat(innerWidth - vl); }
			padded.push(" ".repeat(padding) + content + " ".repeat(padding));
		}
		pi = 0;
		while (pi < padding) { padded.push(padLine); pi += 1; }
		working = padded;
	}

	if (hasBorder) {
		const totalWidth = innerWidth + padding * 2;
		const prefix = stylePrefix(node.style);
		const top = prefix + "┌" + "─".repeat(totalWidth) + "┐" + RESET;
		const bottom = prefix + "└" + "─".repeat(totalWidth) + "┘" + RESET;
		const bordered: string[] = [top];
		for (const line of working) {
			const vl = visibleLen(line);
			const totalContentWidth = totalWidth;
			let content = line;
			if (vl < totalContentWidth) {
				content = line + " ".repeat(totalContentWidth - vl);
			} else if (vl > totalContentWidth) {
				content = line.slice(0, totalContentWidth);
			}
			bordered.push(prefix + "│" + content + "│" + RESET);
		}
		bordered.push(bottom);
		working = bordered;
	}

	return working;
}

export function paintTree(root: TerminalNode, width: number): string[] {
	return paintNode(root, width);
}
