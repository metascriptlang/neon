import { Host, HostNode } from "./hostTypes";
import { MockNode, mockNode, mockHost, render } from "./host";
import { NeonNode } from "./hostTypes";
import { attr } from "./node";
import { collectCss, registerCss } from "./sheet";
import { styleToCss } from "./css";
import { Style } from "./style";
import {
	LINES_CLASS,
	SERVED_HEAD,
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

function escapeText(value: string): string {
	return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

function escapeAttribute(value: string): string {
	return escapeText(value).replaceAll("\"", "&quot;").replaceAll("'", "&#39;");
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
	let open = "<" + tag;
	for (const a of n.attrs) {
		if (a.value === null) { continue; }
		const mapped = domAttrValue(a.name, a.value as string);
		if (mapped === null) { continue; }
		let v = mapped as string;
		if (a.name === "class" && cls !== "") { v = v === "" ? cls : v + " " + cls; cls = ""; }
		open = open + " " + domAttrName(a.name) + "=\"" + escapeAttribute(v) + "\"";
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
	for (const a of n.attrs) {
		if (a.value !== null && (a.name === "name" || a.name === "property" || a.name === "http-equiv" || a.name === "charset")) {
			return "meta " + (a.name === "charset" ? "charset" : a.value as string);
		}
	}
	return "";
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
