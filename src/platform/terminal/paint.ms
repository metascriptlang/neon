import { TerminalNode, TerminalStyle } from "./types";

const ESC = 0x1b;
const RESET = "\x1b[0m";
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";
const ITALIC = "\x1b[3m";
const UNDERLINE = "\x1b[4m";
const BACKGROUND_OFFSET = 10;
const MAX_GAP_HEIGHT = 1000;

function foregroundCode(name: string): int32 {
	match (name) {
		"black" => { return 30; },
		"red" => { return 31; },
		"green" => { return 32; },
		"yellow" => { return 33; },
		"blue" => { return 34; },
		"magenta" => { return 35; },
		"cyan" => { return 36; },
		"white" => { return 37; },
		"gray" => { return 90; },
		"bright-red" => { return 91; },
		"bright-green" => { return 92; },
		"bright-yellow" => { return 93; },
		"bright-blue" => { return 94; },
		"bright-magenta" => { return 95; },
		"bright-cyan" => { return 96; },
		_ => { throw new Error(`terminal paint: "${name}" is not an ansi colour name`); },
	};
}

function colorEscape(name: string, offset: int32): string {
	return "\x1b[" + String(foregroundCode(name) + offset) + "m";
}

function stylePrefix(s: TerminalStyle): string {
	let p = "";
	if (s.bold) { p += BOLD; }
	if (s.dim) { p += DIM; }
	if (s.italic) { p += ITALIC; }
	if (s.underline) { p += UNDERLINE; }
	if (s.color !== "") { p += colorEscape(s.color, 0); }
	if (s.bg !== "") { p += colorEscape(s.bg, BACKGROUND_OFFSET); }
	return p;
}

function cellWidth(cp: int32): int32 {
	if (cp === 0x200d || (cp >= 0x200b && cp <= 0x200f) || (cp >= 0x300 && cp <= 0x36f) || (cp >= 0xfe00 && cp <= 0xfe0f)) { return 0; }
	if ((cp >= 0x1100 && cp <= 0x115f) || (cp >= 0x2e80 && cp <= 0xa4cf) || (cp >= 0xac00 && cp <= 0xd7a3)
		|| (cp >= 0xf900 && cp <= 0xfaff) || (cp >= 0xfe30 && cp <= 0xfe6f) || (cp >= 0xff00 && cp <= 0xff60)
		|| (cp >= 0xffe0 && cp <= 0xffe6) || (cp >= 0x1f300 && cp <= 0x1f64f) || (cp >= 0x1f900 && cp <= 0x1f9ff)
		|| (cp >= 0x20000 && cp <= 0x3fffd)) { return 2; }
	return 1;
}

function codePointAt(s: string, i: int32): int32 {
	const hi = s.charCodeAt(i);
	if (hi >= 0xd800 && hi <= 0xdbff && i + 1 < s.length) {
		const lo = s.charCodeAt(i + 1);
		if (lo >= 0xdc00 && lo <= 0xdfff) { return 0x10000 + (hi - 0xd800) * 0x400 + (lo - 0xdc00); }
	}
	return hi;
}

function escapeEnd(s: string, start: int32): int32 {
	let i = start;
	while (i < s.length && s.charCodeAt(i) !== "m".code) { i += 1; }
	return i < s.length ? i + 1 : i;
}

export function cells(s: string): int32 {
	let total = 0;
	let i = 0;
	while (i < s.length) {
		if (s.charCodeAt(i) === ESC) { i = escapeEnd(s, i); continue; }
		const cp = codePointAt(s, i);
		total += cellWidth(cp);
		i += cp > 0xffff ? 2 : 1;
	}
	return total;
}

function clip(s: string, width: int32): string {
	let out = "";
	let used = 0;
	let full = false;
	let i = 0;
	while (i < s.length) {
		if (s.charCodeAt(i) === ESC) {
			const end = escapeEnd(s, i);
			out += s.slice(i, end);
			i = end;
			continue;
		}
		const cp = codePointAt(s, i);
		const units = cp > 0xffff ? 2 : 1;
		const w = cellWidth(cp);
		if (!full && used + w > width) { full = true; }
		if (!full) {
			out += s.slice(i, i + units);
			used += w;
		}
		i += units;
	}
	return out;
}

function padTo(s: string, width: int32): string {
	const have = cells(s);
	if (have >= width) { return s; }
	return s + " ".repeat(width - have);
}

function wrapText(s: string, width: int32): string[] {
	if (width <= 0) { return [""]; }
	const lines: string[] = [];
	let current = "";
	for (const word of s.split(" ")) {
		if (current === "") {
			current = word;
		} else if (cells(current) + 1 + cells(word) <= width) {
			current += " " + word;
		} else {
			lines.push(current);
			current = word;
		}
	}
	if (current !== "" || lines.length === 0) { lines.push(current); }
	return lines;
}

function splitLines(s: string, width: int32): string[] {
	const result: string[] = [];
	for (const seg of s.split("\n")) {
		for (const w of wrapText(seg, width)) { result.push(w); }
	}
	return result;
}

function styleLine(content: string, width: int32, s: TerminalStyle): string {
	const body = clip(content, width);
	const prefix = stylePrefix(s);
	if (prefix === "") { return body; }
	return prefix + body + RESET;
}

function getAttr(node: TerminalNode, name: string, fallback: string): string {
	if (!node.attrs.has(name)) { return fallback; }
	const v = node.attrs.get(name);
	if (v === null) { return fallback; }
	return v;
}

function getAttrCount(node: TerminalNode, name: string, fallback: int32, max: int32): int32 {
	const v = getAttr(node, name, "");
	if (v === "") { return fallback; }
	let n = 0;
	for (let i = 0; i < v.length; i += 1) {
		const digit = v.charCodeAt(i) - "0".code;
		n = n * 10 + digit;
		if (digit < 0 || digit > 9 || n > max) { throw new Error(`terminal paint: ${name}="${v}" is not a whole number from 0 to ${max}`); }
	}
	return n;
}

function paintLines(text: string, width: int32, style: TerminalStyle): string[] {
	const result: string[] = [];
	for (const line of splitLines(text, width)) { result.push(styleLine(line, width, style)); }
	return result;
}

export function paintNode(node: TerminalNode, width: int32): string[] {
	if (node.style.hidden) { return []; }
	if (node.isText) { return paintLines(node.text, width, node.style); }

	match (node.tag) {
		"text" => { return paintLines(node.text, width, node.style); },
		"span" => { return [styleLine(node.text, width, node.style)]; },
		"hr" => { return [styleLine("─".repeat(width), width, node.style)]; },
		"gap" => {
			const result: string[] = [];
			for (let i = 0; i < getAttrCount(node, "height", 1, MAX_GAP_HEIGHT); i += 1) { result.push(""); }
			return result;
		},
		_ => {},
	};

	const hasBorder = getAttr(node, "border", "false") === "true";
	const padding = getAttrCount(node, "padding", 0, width);
	const flexDirection = getAttr(node, "flexDirection", node.tag === "row" ? "row" : "column");
	const innerWidth = Math.max(0, width - (hasBorder ? 2 : 0) - padding * 2) as int32;

	if (flexDirection === "row") { return paintRow(node, innerWidth, hasBorder, padding); }
	return paintColumn(node, innerWidth, hasBorder, padding);
}

function paintColumn(node: TerminalNode, innerWidth: int32, hasBorder: boolean, padding: int32): string[] {
	const lines: string[] = [];
	for (const child of node.children) {
		for (const line of paintNode(child, innerWidth)) { lines.push(line); }
	}
	return applyBoxDecoration(lines, node, innerWidth, hasBorder, padding);
}

function paintRow(node: TerminalNode, innerWidth: int32, hasBorder: boolean, padding: int32): string[] {
	const shown: TerminalNode[] = [];
	for (const child of node.children) {
		if (!child.style.hidden) { shown.push(child); }
	}
	if (shown.length === 0) { return applyBoxDecoration([], node, innerWidth, hasBorder, padding); }

	const childWidth = innerWidth / shown.length;
	const blocks: string[][] = [];
	let maxLines = 0;
	for (const child of shown) {
		const childLines = paintNode(child, childWidth);
		blocks.push(childLines);
		if (childLines.length > maxLines) { maxLines = childLines.length; }
	}

	const lines: string[] = [];
	for (let row = 0; row < maxLines; row += 1) {
		let line = "";
		for (const block of blocks) {
			line += padTo(row < block.length ? block[row] : "", childWidth);
		}
		lines.push(line);
	}
	return applyBoxDecoration(lines, node, innerWidth, hasBorder, padding);
}

function applyBoxDecoration(
	lines: string[], node: TerminalNode, innerWidth: int32, hasBorder: boolean, padding: int32
): string[] {
	let working = lines;

	if (padding > 0) {
		const padLine = " ".repeat(innerWidth);
		const side = " ".repeat(padding);
		const padded: string[] = [];
		for (let i = 0; i < padding; i += 1) { padded.push(padLine); }
		for (const line of working) { padded.push(side + padTo(line, innerWidth) + side); }
		for (let i = 0; i < padding; i += 1) { padded.push(padLine); }
		working = padded;
	}

	if (hasBorder) {
		const totalWidth = innerWidth + padding * 2;
		const prefix = stylePrefix(node.style);
		const rule = "─".repeat(totalWidth);
		const bordered: string[] = [prefix + "┌" + rule + "┐" + RESET];
		for (const line of working) {
			bordered.push(prefix + "│" + padTo(line, totalWidth) + "│" + RESET);
		}
		bordered.push(prefix + "└" + rule + "┘" + RESET);
		working = bordered;
	}

	return working;
}

export function paintTree(root: TerminalNode, width: int32): string[] {
	return paintNode(root, width);
}
