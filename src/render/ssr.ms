import { Host, HostNode } from "./hostTypes";
import { MockNode, mockNode, mockHost, render } from "./host";
import { NeonNode } from "./hostTypes";
import { htmlTagFor } from "./node";
import { collectCss, registerCss } from "./sheet";
import { styleToCss } from "./css";
import { Style } from "./style";
import { webBaseClass, RN_WEB_BASE_CSS, domAttrName, domAttrValue } from "./web";

export struct SsrMarkup {
	html: string;
	css: string;
}

function ssrHost(register: (id: string, css: string) => void): Host {
	const h = mockHost();
	const createElement = h.createElement;
	h.createElement = (tag: string): HostNode => {
		const node = createElement(tag);
		const base = webBaseClass(tag);
		if (base !== "") { register("neon-base", RN_WEB_BASE_CSS); }
		(node as unknown as MockNode).className = base;
		return node;
	};
	h.setStyleClass = (node: HostNode, id: string, css: string): void => {
		register(id, css);
		const element = node as unknown as MockNode;
		element.className = element.className === "" ? id : element.className + " " + id;
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

function serializeNode(n: MockNode): string {
	if (n.tag === "") { return escapeText(n.text); }
	const tag = htmlTagFor(n.tag);
	let cls = n.className;
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
	if (st !== null) {
		const inline = styleToCss(st as Style);
		if (inline !== "") { open = open + " style=\"" + escapeAttribute(inline) + "\""; }
	}
	if (voidTag(tag)) {
		if (n.children.length > 0) {
			throw new Error("SSR void element '" + tag + "' cannot have children");
		}
		return open + ">";
	}
	return open + ">" + serializeChildren(n) + "</" + tag + ">";
}

export function serializeChildren(n: MockNode): string {
	let s = "";
	for (const k of n.children) { s = s + serializeNode(k); }
	return s;
}

export function renderToString(n: NeonNode): string {
	const box = mockNode("ssr-root");
	const dispose = render(n, SSR_HOST, box as unknown as HostNode, "");
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
	const dispose = render(n, host, box as unknown as HostNode, "");
	try { return { html: serializeChildren(box), css: css }; }
	finally { dispose(); }
}
