import { Host, HostNode } from "./hostTypes";
import { MockNode, mockNode, mockHost, render } from "./host";
import { NeonNode } from "./hostTypes";
import { attr } from "./node";
import { collectCss, registerCss } from "./sheet";
import { styleToCss } from "./css";
import { Style } from "./style";
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

function addClass(element: MockNode, id: string): void {
	element.className = element.className === "" ? id : element.className + " " + id;
}

function ssrHost(register: (id: string, css: string) => void): Host {
	const h = mockHost();
	const createElement = h.createElement;
	h.createElement = (tag: string): HostNode => {
		const node = createElement(tag);
		for (const rule of webRules(tag)) { register(rule.id, rule.css); }
		const base = webBaseClass(tag);
		const control = webControlClass(tag);
		(node as unknown as MockNode).className = base === "" || control === "" ? base + control : base + " " + control;
		for (const fixed of webFixedAttrs(tag)) { (node as unknown as MockNode).attrs.push(fixed); }
		return node;
	};
	h.setStyleClass = (node: HostNode, id: string, css: string): void => {
		register(id, css);
		addClass(node as unknown as MockNode, id);
	};
	const setAttr = h.setAttr;
	h.setAttr = (node: HostNode, name: string, value: string): void => {
		if (name !== "numberOfLines") { setAttr(node, name, value); return; }
		register(TEXT_RULES_ID, TEXT_CSS);
		if (!clampedLines(value)) { return; }
		const rule = linesRule(value);
		register(rule.id, rule.css);
		addClass(node as unknown as MockNode, LINES_CLASS);
		addClass(node as unknown as MockNode, linesClass(value));
	};
	return h;
}

const SSR_HOST: Host = ssrHost(registerCss);

function withEntity(value: string, char: string, entity: string): string {
	return value.indexOf(char) < 0 ? value : value.replaceAll(char, entity);
}

function escapeText(value: string): string {
	return withEntity(withEntity(withEntity(value, "&", "&amp;"), "<", "&lt;"), ">", "&gt;");
}

function escapeAttribute(value: string): string {
	return withEntity(withEntity(escapeText(value), "\"", "&quot;"), "'", "&#39;");
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

function attrValue(n: MockNode, name: string): string | null {
	for (const a of n.attrs) {
		if (a.name === name) { return a.value; }
	}
	return null;
}

function flagOr(n: MockNode, name: string, absent: boolean): boolean {
	const v = attrValue(n, name);
	if (v === null) { return absent; }
	return v === "" || v === "true";
}

function scrollOf(n: MockNode): ScrollLook {
	const keeps = attrValue(n, "maintainVisibleContentPosition");
	return scrollLook(
		attrValue(n, "horizontal") === "true",
		flagOr(n, "scrollEnabled", true),
		flagOr(n, "showsHorizontalScrollIndicator", true),
		flagOr(n, "showsVerticalScrollIndicator", true),
		attrValue(n, "refreshEnabled") === "true",
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

function textareaText(n: MockNode): string {
	const value = attrValue(n, "value");
	if (value !== null && value !== "") { return value as string; }
	const initial = attrValue(n, "defaultValue");
	return initial === null ? "" : initial as string;
}

function textareaBody(n: MockNode): string {
	const text = textareaText(n);
	return text.startsWith("\n") ? "\n" + escapeText(text) : escapeText(text);
}

function serializeNode(n: MockNode): string {
	if (n.tag === "") { return escapeText(n.text); }
	const tag = webHtmlTag(n.tag);
	let cls = n.className;
	let scroll = "";
	if (n.tag === "scrollview") {
		const look = scrollOf(n);
		scroll = scrollLookCss(look);
		if (look.hideHorizontal) { cls = cls + " neon-hide-horizontal"; }
		if (look.hideVertical) { cls = cls + " neon-hide-vertical"; }
	}
	const names: string[] = [];
	const values: string[] = [];
	for (const a of n.attrs) {
		if (a.value === null) { continue; }
		const control = controlAttr(n.tag, a.name, a.value as string);
		if (control !== null) {
			const written = control as ControlAttr;
			if (written.name !== "") { putAttribute(names, values, written.name, written.value); }
			continue;
		}
		const mapped = domAttrValue(a.name, a.value as string);
		let v = mapped === null ? "" : mapped as string;
		if (mapped !== null && a.name === "class" && cls !== "") { v = v === "" ? cls : v + " " + cls; cls = ""; }
		putAttribute(names, values, domAttrName(a.name), mapped === null ? null : v);
	}
	let open = "<" + tag;
	for (let i = 0; i < names.length; i += 1) {
		open = open + " " + names[i] + "=\"" + escapeAttribute(values[i]) + "\"";
	}
	if (cls !== "") { open = open + " class=\"" + escapeAttribute(cls) + "\""; }
	const st = n.style;
	const inline = (st === null ? "" : styleToCss(st as Style)) + scroll;
	if (inline !== "") { open = open + " style=\"" + escapeAttribute(inline) + "\""; }
	if (voidTag(tag)) {
		if (n.children.length > 0) {
			throw new Error("SSR void element '" + tag + "' cannot have children");
		}
		return open + ">";
	}
	if (n.tag === "multilinetextinput") { return open + ">" + textareaBody(n) + "</" + tag + ">"; }
	return open + ">" + serializeChildren(n, !rawTextTag(tag)) + "</" + tag + ">";
}

const EMPTY_TEXT = "<!---->";
const TEXT_BREAK = "<!--!-->";

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

function headKey(n: MockNode): string {
	if (n.tag === "title") { return "title"; }
	if (n.tag !== "meta") { return ""; }
	let named: string | null = null;
	let property: string | null = null;
	let httpEquiv: string | null = null;
	let content: string | null = null;
	let charset: string | null = null;
	let media: string | null = null;
	for (const a of n.attrs) {
		if (a.name === "name") { named = a.value; }
		else if (a.name === "property") { property = a.value; }
		else if (a.name === "http-equiv") { httpEquiv = a.value; }
		else if (a.name === "content") { content = a.value; }
		else if (a.name === "charset") { charset = a.value; }
		else if (a.name === "media") { media = a.value; }
	}
	if (named === null) { named = property; }
	if (named === null && httpEquiv === null && charset === null) { return ""; }
	return keyPart(named) + keyPart(httpEquiv) + keyPart(content) + keyPart(charset) + keyPart(media);
}

function keyPart(value: string | null): string {
	return value === null ? "\n-" : "\n+" + value;
}

function serializeHead(head: MockNode): string {
	const seen = new Map<string, boolean>();
	let s = "";
	for (const k of head.children) {
		if (k.tag === "") { continue; }
		const key = headKey(k);
		if (key !== "") {
			if (seen.has(key)) { continue; }
			seen.set(key, true);
		}
		k.attrs.push(attr(SERVED_HEAD, ""));
		s = s + serializeNode(k);
	}
	return s;
}

function renderInto(box: MockNode, n: NeonNode, host: Host): Dispose {
	return asServer((): Dispose => render(n, host, box as unknown as HostNode, ""));
}

export function renderToString(n: NeonNode): string {
	const box = mockNode("ssr-root");
	const dispose = renderInto(box, n, SSR_HOST);
	try { return serializeChildren(box); }
	finally { dispose(); }
}

export function renderToMarkup(n: NeonNode): SsrMarkup {
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
