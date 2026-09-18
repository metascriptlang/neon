import { Host, HostNode } from "./hostTypes";
import { MockNode, mockNode, mockHost, renderToHost } from "./host";
import { NeonNode } from "./hostTypes";
import { htmlTagFor } from "./node";
import { registerCss } from "./sheet";
import { styleToCss } from "./css";
import { Style } from "./style";
import { createRoot } from "../core/owner";

function ssrHost(): Host {
	const h = mockHost();
	h.setStyleClass = (node: HostNode, id: string, css: string): void => {
		registerCss(id, css);
		(node as unknown as MockNode).className = id;
	};
	return h;
}

const SSR_HOST: Host = ssrHost();

function serializeNode(n: MockNode): string {
	if (n.tag === "") { return n.text; }
	const tag = htmlTagFor(n.tag);
	let cls = n.className;
	let open = "<" + tag;
	for (const a of n.attrs) {
		if (a.value === null) { continue; }
		let v = a.value as string;
		if (a.name === "class" && cls !== "") { v = v === "" ? cls : v + " " + cls; cls = ""; }
		open = open + " " + a.name + "=\"" + v + "\"";
	}
	if (cls !== "") { open = open + " class=\"" + cls + "\""; }
	const st = n.style;
	if (st !== null) {
		const inline = styleToCss(st as Style);
		if (inline !== "") { open = open + " style=\"" + inline + "\""; }
	}
	return open + ">" + serializeChildren(n) + "</" + tag + ">";
}

export function serializeChildren(n: MockNode): string {
	let s = "";
	for (const k of n.children) { s = s + serializeNode(k); }
	return s;
}

export function renderToString(n: NeonNode): string {
	return createRoot((dispose) => {
		const box = mockNode("ssr-root");
		renderToHost(n, SSR_HOST, box as unknown as HostNode);
		const out = serializeChildren(box);
		dispose();
		return out;
	});
}
