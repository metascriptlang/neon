// react-native-svg's SvgXml: an SVG document as text, parsed here into scene nodes and
// drawn by the same <Svg> path. Element names are matched case-insensitively, attribute
// names go from kebab-case to the camelCase props (`stroke-width` → `strokeWidth`,
// `xlink:href` → `href`), and a `style` attribute's declarations override attributes.
// Malformed XML is an error that names the position.

import { Accessor } from "../../core/signal";
import { createEffect } from "../../core/effect";
import { Style } from "../../render/style";
import { Host, HostNode } from "../../render/hostTypes";
import { NeonNode } from "../../render/node";
import { AccessibilityRole } from "../primitives";
import { SvgNode } from "./scene";
import { Svg, NumberProp } from "./elements";

struct XmlCursor {
	text: string;
	at: int32;
}

function fail(c: XmlCursor, what: string): void {
	throw `SvgXml: ${what} at ${c.at}`;
}

function isNameChar(code: int32): boolean {
	return (code >= 97 && code <= 122) || (code >= 65 && code <= 90) || (code >= 48 && code <= 57) ||
		code === 45 || code === 95 || code === 58 || code === 46;
}

function isSpace(code: int32): boolean {
	return code === 32 || code === 9 || code === 10 || code === 13;
}

function skipSpace(ref c: XmlCursor): void {
	while (c.at < c.text.length && isSpace(c.text.charCodeAt(c.at))) { c.at += 1; }
}

function startsWithAt(c: XmlCursor, word: string): boolean {
	return c.text.substring(c.at, c.at + word.length) === word;
}

function readName(ref c: XmlCursor): string {
	const start = c.at;
	while (c.at < c.text.length && isNameChar(c.text.charCodeAt(c.at))) { c.at += 1; }
	if (start === c.at) { fail(c, "expected a name"); }
	return c.text.substring(start, c.at);
}

function skipPast(ref c: XmlCursor, end: string): void {
	const at = c.text.indexOf(end, c.at);
	if (at < 0) { fail(c, `unterminated, expected "${end}"`); }
	c.at = (at + end.length) as int32;
}

function hexValue(digits: string): int32 {
	let v = 0;
	for (let i = 0; i < digits.length; i += 1) {
		const code = digits.charCodeAt(i);
		const d = code >= 48 && code <= 57 ? code - 48 : code >= 97 && code <= 102 ? code - 87 : code >= 65 && code <= 70 ? code - 55 : 0;
		v = v * 16 + d;
	}
	return v;
}

export function decodeEntities(s: string): string {
	if (s.indexOf("&") < 0) { return s; }
	let out = "";
	let i = 0;
	while (i < s.length) {
		const amp = s.indexOf("&", i);
		if (amp < 0) {
			out += s.substring(i, s.length);
			break;
		}
		out += s.substring(i, amp);
		const semi = s.indexOf(";", amp);
		if (semi < 0) {
			out += s.substring(amp, s.length);
			break;
		}
		const name = s.substring(amp + 1, semi);
		if (name === "lt") { out += "<"; }
		else if (name === "gt") { out += ">"; }
		else if (name === "amp") { out += "&"; }
		else if (name === "quot") { out += "\""; }
		else if (name === "apos") { out += "'"; }
		else if (name.startsWith("#x")) { out += String.fromCharCode(hexValue(name.substring(2, name.length))); }
		else if (name.startsWith("#")) { out += String.fromCharCode(parseInt(name.substring(1, name.length)) as int32); }
		else { out += s.substring(amp, semi + 1); }
		i = (semi + 1) as int32;
	}
	return out;
}

export function camelName(name: string): string {
	if (name === "xlink:href") { return "href"; }
	const colon = name.indexOf(":");
	const local = colon >= 0 ? name.substring(colon + 1, name.length) : name;
	const parts: string[] = local.split("-");
	let out = parts[0];
	for (let i = 1; i < parts.length; i += 1) {
		const p = parts[i];
		if (p !== "") { out += p.substring(0, 1).toUpperCase() + p.substring(1, p.length); }
	}
	return out;
}

function applyStyleAttr(n: SvgNode, css: string): void {
	for (const declaration of css.split(";")) {
		const colon = declaration.indexOf(":");
		if (colon < 0) { continue; }
		const name = declaration.substring(0, colon).trim();
		const value = declaration.substring(colon + 1, declaration.length).trim();
		if (name !== "" && value !== "") { n.attrs.set(camelName(name), value); }
	}
}

function readAttributes(ref c: XmlCursor, n: SvgNode): boolean {
	let style = "";
	while (true) {
		skipSpace(c);
		if (c.at >= c.text.length) { fail(c, "unterminated tag"); }
		if (startsWithAt(c, "/>")) {
			c.at += 2;
			if (style !== "") { applyStyleAttr(n, style); }
			return true;
		}
		if (startsWithAt(c, ">")) {
			c.at += 1;
			if (style !== "") { applyStyleAttr(n, style); }
			return false;
		}
		const name = readName(c);
		skipSpace(c);
		if (!startsWithAt(c, "=")) { fail(c, `attribute "${name}" has no value`); }
		c.at += 1;
		skipSpace(c);
		const quote = c.text.substring(c.at, c.at + 1);
		if (quote !== "\"" && quote !== "'") { fail(c, `attribute "${name}" is not quoted`); }
		const end = c.text.indexOf(quote, c.at + 1);
		if (end < 0) { fail(c, `attribute "${name}" is not closed`); }
		const value = decodeEntities(c.text.substring(c.at + 1, end));
		c.at = (end + 1) as int32;
		if (name === "style") { style = value; }
		else if (name !== "class" && !name.startsWith("xmlns")) { n.attrs.set(camelName(name), value); }
	}
	return false;
}

function readChildren(ref c: XmlCursor, parent: SvgNode): void {
	while (c.at < c.text.length) {
		if (startsWithAt(c, "</")) {
			c.at += 2;
			const name = readName(c);
			if (name.toLowerCase() !== parent.tag) { fail(c, `</${name}> closes <${parent.tag}>`); }
			skipSpace(c);
			if (!startsWithAt(c, ">")) { fail(c, "expected >"); }
			c.at += 1;
			return;
		}
		if (startsWithAt(c, "<!--")) { skipPast(c, "-->"); continue; }
		if (startsWithAt(c, "<![CDATA[")) {
			const start = c.at + 9;
			skipPast(c, "]]>");
			const t = new SvgNode("");
			t.isText = true;
			t.text = c.text.substring(start, c.at - 3);
			t.parent = parent;
			parent.children.push(t);
			continue;
		}
		if (startsWithAt(c, "<?") || startsWithAt(c, "<!")) { skipPast(c, ">"); continue; }
		if (startsWithAt(c, "<")) {
			c.at += 1;
			const child = new SvgNode(readName(c).toLowerCase());
			const closed = readAttributes(c, child);
			if (!closed) { readChildren(c, child); }
			if (child.tag !== "style" && child.tag !== "title" && child.tag !== "desc" && child.tag !== "metadata") {
				child.parent = parent;
				parent.children.push(child);
			}
			continue;
		}
		const next = c.text.indexOf("<", c.at);
		const end = next < 0 ? c.text.length : next;
		const raw = c.text.substring(c.at, end);
		c.at = end as int32;
		if (parent.tag === "text" || parent.tag === "tspan") {
			const t = new SvgNode("");
			t.isText = true;
			t.text = decodeEntities(raw);
			t.parent = parent;
			parent.children.push(t);
		}
	}
	if (parent.tag !== "#document") { fail(c, `<${parent.tag}> is not closed`); }
}

// The document's root <svg> element with its subtree.
export function parseSvgXml(text: string): SvgNode {
	const doc = new SvgNode("#document");
	let c: XmlCursor = { text, at: 0 };
	readChildren(c, doc);
	for (const child of doc.children) {
		if (child.tag === "svg") {
			child.parent = null;
			return child;
		}
	}
	throw "SvgXml: the document has no <svg> element";
}

// The parsed document's children, placed into the scene <Svg> gives them; the document
// root's attributes (viewBox, fill, …) land on the scene root unless a prop already set them.
function documentContent(xml: Accessor<string>, owned: string[]): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		let placed: SvgNode[] = [];
		let written: string[] = [];
		createEffect((): void => {
			const doc = parseSvgXml(xml());
			for (const n of placed) { host.removeChild(parent, n as unknown as HostNode); }
			for (const name of written) { host.removeAttr(parent, name); }
			placed = [];
			written = [];
			doc.attrs.forEach((value: string, name: string): void => {
				if (owned.indexOf(name) >= 0) { return; }
				host.setAttr(parent, name, value);
				written.push(name);
			});
			const children: SvgNode[] = [];
			for (const child of doc.children) { children.push(child); }
			for (const child of children) {
				host.insertBefore(parent, child as unknown as HostNode, before);
				placed.push(child);
			}
		});
	};
}

export interface SvgXmlProps {
	xml: Accessor<string>;
	width?: Accessor<NumberProp> | null;
	height?: Accessor<NumberProp> | null;
	color?: Accessor<string> | null;
	style?: Accessor<Style> | null;
	accessible?: Accessor<boolean> | null;
	accessibilityLabel?: Accessor<string> | null;
	accessibilityRole?: Accessor<AccessibilityRole> | null;
}

export function SvgXml(props: SvgXmlProps): NeonNode {
	const owned: string[] = [];
	if (props.width !== null) { owned.push("width"); }
	if (props.height !== null) { owned.push("height"); }
	if (props.color !== null) { owned.push("color"); }
	return Svg({
		width: props.width,
		height: props.height,
		color: props.color,
		style: props.style,
		accessible: props.accessible,
		accessibilityLabel: props.accessibilityLabel,
		accessibilityRole: props.accessibilityRole,
		children: documentContent(props.xml, owned),
	});
}
