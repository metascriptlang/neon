import { Host, HostNode } from "./hostTypes";
import { MockNode, mockNode, mockHost, render } from "./host";
import { NeonNode } from "./hostTypes";
import { NeonEvent } from "./event";
import { collectCss, registerCss } from "./sheet";
import { styleToCss } from "./css";
import { Style, StyleValue, emptyStyle, setStyleField } from "./style";
import {
	ControlAttr,
	LINES_CLASS,
	SERVED_HEAD,
	controlAttr,
	webFixedAttrs,
	ScrollLook,
	TEXT_CSS,
	TEXT_RULES_ID,
	clampedLines,
	linesClass,
	linesRule,
	scrollLook,
	scrollLookCss,
	webBaseClass,
	webControlClass,
	webHtmlTag,
	webRules,
	domAttrName,
	domAttrValue,
} from "./web";
import { parseVisibleContent } from "./visibleContent";
import { asServer } from "./environment";
import { Dispose } from "../core/types";

export struct SsrMarkup {
	html: string;
	css: string;
	head: string;
}

function joinClass(className: string, id: string): string {
	return className === "" ? id : className + " " + id;
}

function baseClassOf(tag: string): string {
	const base = webBaseClass(tag);
	const control = webControlClass(tag);
	return base === "" || control === "" ? base + control : base + " " + control;
}

function entityOf(c: int32, quoted: boolean): string {
	return match (c) {
		38 => "&amp;",
		60 => "&lt;",
		62 => "&gt;",
		34 => quoted ? "&quot;" : "",
		39 => quoted ? "&#39;" : "",
		_ => "",
	};
}

function escaped(value: string, quoted: boolean): string {
	let out = "";
	let last = 0;
	const n = value.length;
	for (let i = 0; i < n; i += 1) {
		const c = value.charCodeAt(i);
		if (c > 62 || c < 34) { continue; }
		const e = entityOf(c, quoted);
		if (e === "") { continue; }
		out = out + value.slice(last, i) + e;
		last = i + 1;
	}
	if (last === 0) { return value; }
	return out + value.slice(last);
}

function escapeText(value: string): string {
	return escaped(value, false);
}

function escapeAttribute(value: string): string {
	return escaped(value, true);
}

function voidTag(tag: string): boolean {
	return match (tag.toLowerCase()) {
		"area" | "base" | "br" | "col" | "embed" | "hr" | "img" | "input" |
		"link" | "meta" | "param" | "source" | "track" | "wbr" => true,
		_ => false,
	};
}

function rawTextTag(tag: string): boolean {
	return match (tag.toLowerCase()) {
		"script" | "style" | "textarea" | "title" => true,
		_ => false,
	};
}

function attrValue(names: string[], values: string[], name: string): string | null {
	const at = names.indexOf(name);
	return at < 0 ? null : values[at];
}

function flagOr(names: string[], values: string[], name: string, absent: boolean): boolean {
	const v = attrValue(names, values, name);
	if (v === null) { return absent; }
	return v === "" || v === "true";
}

function scrollOf(names: string[], values: string[]): ScrollLook {
	const keeps = attrValue(names, values, "maintainVisibleContentPosition");
	return scrollLook(
		attrValue(names, values, "horizontal") === "true",
		flagOr(names, values, "scrollEnabled", true),
		flagOr(names, values, "showsHorizontalScrollIndicator", true),
		flagOr(names, values, "showsVerticalScrollIndicator", true),
		attrValue(names, values, "refreshEnabled") === "true",
		keeps !== null && parseVisibleContent(keeps as string) !== null,
	);
}

function putAttribute(names: string[], values: string[], name: string, value: string | null): void {
	const at = names.indexOf(name);
	if (value === null) {
		if (at >= 0) { names.splice(at, 1); values.splice(at, 1); }
		return;
	}
	if (at >= 0) { values[at] = value as string; return; }
	names.push(name);
	values.push(value as string);
}

function upsertAttr(names: string[], values: string[], name: string, value: string): void {
	const at = names.indexOf(name);
	if (at >= 0) { values[at] = value; return; }
	names.push(name);
	values.push(value);
}

function removeAttr(names: string[], values: string[], name: string): void {
	const at = names.indexOf(name);
	if (at < 0) { return; }
	names.splice(at, 1);
	values.splice(at, 1);
}

function textareaBody(names: string[], values: string[]): string {
	const value = attrValue(names, values, "value");
	const initial = attrValue(names, values, "defaultValue");
	const text = value !== null && value !== "" ? value as string : initial === null ? "" : initial as string;
	return text.startsWith("\n") ? "\n" + escapeText(text) : escapeText(text);
}

// One element's markup from what its host calls left on it: the tree path reads a
// MockNode, the writer its own record, and both come through here.
function elementMarkup(
	wire: string,
	names: string[],
	values: string[],
	className: string,
	style: Style | null,
	inner: string,
	childCount: int32,
): string {
	const tag = webHtmlTag(wire);
	let cls = className;
	let scroll = "";
	if (wire === "scrollview") {
		const look = scrollOf(names, values);
		scroll = scrollLookCss(look);
		if (look.hideHorizontal) { cls = cls + " neon-hide-horizontal"; }
		if (look.hideVertical) { cls = cls + " neon-hide-vertical"; }
	}
	const outNames: string[] = [];
	const outValues: string[] = [];
	for (let i = 0; i < names.length; i += 1) {
		const raw = values[i];
		const control = controlAttr(wire, names[i], raw);
		if (control !== null) {
			const written = control as ControlAttr;
			if (written.name !== "") { putAttribute(outNames, outValues, written.name, written.value); }
			continue;
		}
		const mapped = domAttrValue(names[i], raw);
		let v = mapped === null ? "" : mapped as string;
		if (mapped !== null && names[i] === "class" && cls !== "") { v = v === "" ? cls : v + " " + cls; cls = ""; }
		putAttribute(outNames, outValues, domAttrName(names[i]), mapped === null ? null : v);
	}
	let open = "<" + tag;
	for (let i = 0; i < outNames.length; i += 1) {
		open = open + " " + outNames[i] + "=\"" + escapeAttribute(outValues[i]) + "\"";
	}
	if (cls !== "") { open = open + " class=\"" + escapeAttribute(cls) + "\""; }
	const inline = (style === null ? "" : styleToCss(style as Style)) + scroll;
	if (inline !== "") { open = open + " style=\"" + escapeAttribute(inline) + "\""; }
	if (voidTag(tag)) {
		if (childCount > 0) {
			throw new Error("SSR void element '" + tag + "' cannot have children");
		}
		return open + ">";
	}
	if (wire === "multilinetextinput") { return open + ">" + textareaBody(names, values) + "</" + tag + ">"; }
	return open + ">" + inner + "</" + tag + ">";
}

const EMPTY_TEXT = "<!---->";
const TEXT_BREAK = "<!--!-->";

function headKey(tag: string, names: string[], values: string[]): string {
	if (tag === "title") { return "title"; }
	if (tag !== "meta") { return ""; }
	let named = attrValue(names, values, "name");
	const httpEquiv = attrValue(names, values, "http-equiv");
	const charset = attrValue(names, values, "charset");
	if (named === null) { named = attrValue(names, values, "property"); }
	if (named === null && httpEquiv === null && charset === null) { return ""; }
	return keyPart(named) + keyPart(httpEquiv) + keyPart(attrValue(names, values, "content")) +
		keyPart(charset) + keyPart(attrValue(names, values, "media"));
}

function keyPart(value: string | null): string {
	return value === null ? "\n-" : "\n+" + value;
}

// ---- The tree path: a mock host tree, serialized after the mount ----

function ssrHost(register: (id: string, css: string) => void): Host {
	const h = mockHost();
	const createElement = h.createElement;
	h.createElement = (tag: string): HostNode => {
		const node = createElement(tag);
		for (const rule of webRules(tag)) { register(rule.id, rule.css); }
		(node as unknown as MockNode).className = baseClassOf(tag);
		for (const fixed of webFixedAttrs(tag)) { (node as unknown as MockNode).attrs.push(fixed); }
		return node;
	};
	h.setStyleClass = (node: HostNode, id: string, css: string): void => {
		if (id === "") { return; }
		register(id, css);
		const n = node as unknown as MockNode;
		n.className = joinClass(n.className, id);
	};
	const setAttr = h.setAttr;
	h.setAttr = (node: HostNode, name: string, value: string): void => {
		if (name !== "numberOfLines") { setAttr(node, name, value); return; }
		register(TEXT_RULES_ID, TEXT_CSS);
		if (!clampedLines(value)) { return; }
		const rule = linesRule(value);
		register(rule.id, rule.css);
		const n = node as unknown as MockNode;
		n.className = joinClass(joinClass(n.className, LINES_CLASS), linesClass(value));
	};
	return h;
}

const SSR_HOST: Host = ssrHost(registerCss);

function attrNames(n: MockNode): string[] {
	const names: string[] = [];
	for (const a of n.attrs) { if (a.value !== null) { names.push(a.name); } }
	return names;
}

function attrValues(n: MockNode): string[] {
	const values: string[] = [];
	for (const a of n.attrs) { if (a.value !== null) { values.push(a.value as string); } }
	return values;
}

function serializeNode(n: MockNode): string {
	if (n.tag === "") { return escapeText(n.text); }
	const tag = webHtmlTag(n.tag);
	const inner = voidTag(tag) || n.tag === "multilinetextinput" ? "" : serializeChildren(n, !rawTextTag(tag));
	return elementMarkup(n.tag, attrNames(n), attrValues(n), n.className, n.style, inner, n.children.length);
}

export function serializeChildren(n: MockNode, marked: boolean = true): string {
	let s = "";
	let afterText = false;
	for (const k of n.children) {
		const isText = k.tag === "";
		if (marked && isText) {
			if (k.text === "") { s = s + EMPTY_TEXT; afterText = false; continue; }
			if (afterText) { s = s + TEXT_BREAK; }
		}
		s = s + serializeNode(k);
		afterText = isText;
	}
	return s;
}

function serializeHead(head: MockNode): string {
	const seen = new Map<string, boolean>();
	let s = "";
	for (const k of head.children) {
		if (k.tag === "") { continue; }
		const names = attrNames(k);
		const values = attrValues(k);
		const key = headKey(k.tag, names, values);
		if (key !== "") {
			if (seen.has(key)) { continue; }
			seen.set(key, true);
		}
		names.push(SERVED_HEAD);
		values.push("");
		const tag = webHtmlTag(k.tag);
		const inner = voidTag(tag) ? "" : serializeChildren(k, !rawTextTag(tag));
		s = s + elementMarkup(k.tag, names, values, k.className, k.style, inner, k.children.length);
	}
	return s;
}

function renderInto(box: MockNode, n: NeonNode, host: Host): Dispose {
	return asServer((): Dispose => render(n, host, box as unknown as HostNode, ""));
}

function treeToString(n: NeonNode): string {
	const box = mockNode("ssr-root");
	const dispose = renderInto(box, n, SSR_HOST);
	try { return serializeChildren(box); }
	finally { dispose(); }
}

function treeToMarkup(n: NeonNode): SsrMarkup {
	const seen = new Map<string, boolean>();
	let css = collectCss();
	const host = ssrHost((id: string, rule: string): void => {
		if (seen.has(id)) { return; }
		seen.set(id, true);
		css = css + rule;
	});
	const box = mockNode("ssr-root");
	const dispose = renderInto(box, n, host);
	try {
		const head = (host.headRoot as (n: HostNode) => HostNode)(box as unknown as HostNode) as unknown as MockNode;
		return { html: serializeChildren(box), css: css, head: serializeHead(head) };
	}
	finally { dispose(); }
}

// ---- The writer: each element becomes markup the moment it is placed ----
//
// A NeonNode on the server performs its host calls in document order: an element
// gets its attributes, then its children, then is placed into its parent. The
// writer keeps one record per node and, at placement, appends the node's markup to
// its parent's body; nothing of the tree outlives that call. The two places that
// put a node somewhere other than at the end of an open element get their own
// node: the head root collects its children for the head block, and the overlay
// root drops what a Portal mounts there, as the tree path does.

class SsrNode {
	tag: string;
	text: string = "";
	names: string[] = [];
	values: string[] = [];
	className: string = "";
	style: Style | null = null;
	body: string = "";
	count: int32 = 0;
	marked: boolean = true;
	afterText: boolean = false;
	parent: SsrNode | null = null;
	prev: SsrNode | null = null;
	next: SsrNode | null = null;
	last: SsrNode | null = null;
	at: int32 = 0;
	index: int32 = 0;
	textBefore: boolean = false;
	owed: int32 = 0;
	collects: boolean = false;
	drops: boolean = false;
	kids: SsrNode[] = [];

	constructor(tag: string) {
		this.tag = tag;
	}
}

class SsrWrite {
	register: (id: string, css: string) => void;
	head: SsrNode = new SsrNode("head");
	overlay: SsrNode = new SsrNode("overlay");
	done: boolean = false;

	constructor(register: (id: string, css: string) => void) {
		this.register = register;
		this.head.collects = true;
		this.overlay.drops = true;
	}
}

function writable(n: SsrNode): SsrNode {
	if (n.parent !== null) {
		throw new Error("SSR writer: <" + n.tag + "> changed after it was written; the server writes each node once, in document order");
	}
	return n;
}

function collect(p: SsrNode, n: SsrNode, ref: HostNode | null): void {
	n.parent = p;
	const at = ref === null ? -1 : p.kids.indexOf(ref as unknown as SsrNode);
	if (at < 0) { p.kids.push(n); } else { p.kids.splice(at, 0, n); }
}

function writeInto(p: SsrNode, n: SsrNode, ref: HostNode | null): void {
	if (p.drops) { return; }
	if (p.collects) { collect(p, n, ref); return; }
	if (ref !== null) {
		throw new Error("SSR writer: <" + p.tag + "> got a child in front of another; the server writes in document order");
	}
	if (p.parent !== null) {
		throw new Error("SSR writer: <" + p.tag + "> got a child after it was written; the server writes each node once, in document order");
	}
	if (p.owed > 0) {
		throw new Error("SSR writer: a child of <" + p.tag + "> was removed from the middle; the server can only take back its last nodes");
	}
	if (n.parent !== null) {
		throw new Error("SSR writer: a node was placed into <" + p.tag + "> while it still stood elsewhere");
	}
	n.parent = p;
	n.at = p.body.length;
	n.index = p.count;
	n.textBefore = p.afterText;
	n.prev = p.last;
	n.next = null;
	if (p.last !== null) { (p.last as SsrNode).next = n; }
	p.last = n;
	p.count += 1;
	if (n.tag === "") {
		if (p.marked) {
			if (n.text === "") { p.body += EMPTY_TEXT; p.afterText = false; return; }
			if (p.afterText) { p.body += TEXT_BREAK; }
		}
		p.body += escapeText(n.text);
		p.afterText = true;
		return;
	}
	p.body += elementMarkup(n.tag, n.names, n.values, n.className, n.style, n.body, n.count);
	n.body = "";
	p.afterText = false;
}

// A region that re-renders on the server takes back the rows it just wrote, which
// are the last children of their parent: removing one drops it and everything
// written after it, and those later nodes are owed removals that must follow before
// anything else is written there.
function takeBack(p: SsrNode, n: SsrNode): void {
	if (n.parent !== p) {
		throw new Error("SSR writer: a node removed from <" + p.tag + "> is not its child");
	}
	n.parent = null;
	if (n.index >= p.count) {
		p.owed -= 1;
		return;
	}
	p.owed += p.count - n.index - 1;
	p.body = p.body.slice(0, n.at);
	p.count = n.index;
	p.afterText = n.textBefore;
	p.last = n.prev;
	if (n.prev !== null) { (n.prev as SsrNode).next = null; }
}

function writerHost(w: SsrWrite): Host {
	return {
		createElement: (tag: string): HostNode => {
			const n = new SsrNode(tag);
			for (const rule of webRules(tag)) { w.register(rule.id, rule.css); }
			n.className = baseClassOf(tag);
			for (const fixed of webFixedAttrs(tag)) {
				n.names.push(fixed.name);
				n.values.push(fixed.value as string);
			}
			n.marked = !rawTextTag(webHtmlTag(tag));
			return n as unknown as HostNode;
		},
		createText: (s: string): HostNode => {
			const n = new SsrNode("");
			n.text = s;
			return n as unknown as HostNode;
		},
		setText: (node: HostNode, s: string): void => {
			writable(node as unknown as SsrNode).text = s;
		},
		setAttr: (node: HostNode, name: string, value: string): void => {
			const n = writable(node as unknown as SsrNode);
			if (name !== "numberOfLines") { upsertAttr(n.names, n.values, name, value); return; }
			w.register(TEXT_RULES_ID, TEXT_CSS);
			if (!clampedLines(value)) { return; }
			const rule = linesRule(value);
			w.register(rule.id, rule.css);
			n.className = joinClass(joinClass(n.className, LINES_CLASS), linesClass(value));
		},
		removeAttr: (node: HostNode, name: string): void => {
			const n = writable(node as unknown as SsrNode);
			removeAttr(n.names, n.values, name);
		},
		setStyle: (node: HostNode, style: Style): void => {
			writable(node as unknown as SsrNode).style = style;
		},
		setStyleProp: (node: HostNode, name: string, value: StyleValue): void => {
			const n = writable(node as unknown as SsrNode);
			if (n.style === null) { n.style = emptyStyle(); }
			setStyleField(n.style as Style, name, value);
		},
		setStyleClass: (node: HostNode, id: string, css: string): void => {
			if (id === "") { return; }
			w.register(id, css);
			const n = writable(node as unknown as SsrNode);
			n.className = joinClass(n.className, id);
		},
		addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {},
		append: (parent: HostNode, child: HostNode): void => {
			writeInto(parent as unknown as SsrNode, child as unknown as SsrNode, null);
		},
		insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null): void => {
			writeInto(parent as unknown as SsrNode, node as unknown as SsrNode, ref);
		},
		removeChild: (parent: HostNode, node: HostNode): void => {
			const p = parent as unknown as SsrNode;
			const n = node as unknown as SsrNode;
			if (p.drops) { return; }
			if (p.collects) {
				const at = p.kids.indexOf(n);
				if (at >= 0) { p.kids.splice(at, 1); }
				n.parent = null;
				return;
			}
			if (w.done) { return; }
			takeBack(p, n);
		},
		nextSibling: (node: HostNode): HostNode | null => {
			const n = node as unknown as SsrNode;
			const p = n.parent;
			if (p !== null && (p as SsrNode).collects) {
				const kids = (p as SsrNode).kids;
				const at = kids.indexOf(n);
				return at >= 0 && at + 1 < kids.length ? kids[at + 1] as unknown as HostNode : null;
			}
			return n.next === null ? null : n.next as unknown as HostNode;
		},
		firstChild: (node: HostNode): HostNode | null => {
			const n = node as unknown as SsrNode;
			if (n.drops) { return null; }
			if (!n.collects) {
				throw new Error("SSR writer: <" + n.tag + "> was read back as a tree; only the head root keeps its children");
			}
			return n.kids.length === 0 ? null : n.kids[0] as unknown as HostNode;
		},
		cloneNode: null,
		voidArea: null,
		scrollTo: null,
		overlayRoot: (node: HostNode): HostNode => w.overlay as unknown as HostNode,
		headRoot: (node: HostNode): HostNode => w.head as unknown as HostNode,
	};
}

function writtenHead(head: SsrNode): string {
	const seen = new Map<string, boolean>();
	let s = "";
	for (const k of head.kids) {
		if (k.tag === "") { continue; }
		const key = headKey(k.tag, k.names, k.values);
		if (key !== "") {
			if (seen.has(key)) { continue; }
			seen.set(key, true);
		}
		const names = k.names.slice(0, k.names.length);
		const values = k.values.slice(0, k.values.length);
		names.push(SERVED_HEAD);
		values.push("");
		s = s + elementMarkup(k.tag, names, values, k.className, k.style, k.body, k.count);
	}
	return s;
}

function writeRender(n: NeonNode, w: SsrWrite): SsrMarkup {
	const root = new SsrNode("ssr-root");
	const dispose = asServer((): Dispose => render(n, writerHost(w), root as unknown as HostNode, ""));
	try {
		return { html: root.body, css: "", head: writtenHead(w.head) };
	}
	finally {
		w.done = true;
		dispose();
	}
}

function writeToString(n: NeonNode): string {
	return writeRender(n, new SsrWrite(registerCss)).html;
}

function writeToMarkup(n: NeonNode): SsrMarkup {
	const seen = new Map<string, boolean>();
	let css = collectCss();
	const w = new SsrWrite((id: string, rule: string): void => {
		if (seen.has(id)) { return; }
		seen.set(id, true);
		css = css + rule;
	});
	const markup = writeRender(n, w);
	return { html: markup.html, css: css, head: markup.head };
}

// A -d:server build renders through the writer; any other build, where the client
// runtime's template tier builds a skeleton before it fills the holes, renders
// through the tree path. tests/ssrParity holds the two to the same bytes.
export function renderToString(n: NeonNode): string {
	when (server) { return writeToString(n); } else { return treeToString(n); }
}

export function renderToMarkup(n: NeonNode): SsrMarkup {
	when (server) { return writeToMarkup(n); } else { return treeToMarkup(n); }
}
