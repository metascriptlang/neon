import { Accessor, accessor } from "../core/signal";

export class SafeError extends Error {}

// server/signals.ts:3535 ssrSanitizeError: a build without `debug` hands the fallback one generic Error per caught error
export function serverCaught(error: Error): Accessor<Error> {
	let wire = error;
	when (debug) {} else { if (!(error instanceof SafeError)) { wire = new Error("Internal Server Error"); } }
	return accessor((): Error => wire);
}

export struct SsrMarkup {
	html: string;
	css: string;
	head: string;
}

when (server) {
	import { Host, HostNode, NeonNode } from "./hostTypes";
	import { render } from "./host";
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
		WebRule,
		domAttrName,
		domAttrValue,
	} from "./web";
	import { parseVisibleContent } from "./visibleContent";
	import { asServer } from "./environment";
	import { Dispose } from "../core/types";

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

	function scriptOrStyle(tag: string): string {
		const name = tag.toLowerCase();
		return name === "script" || name === "style" ? name : "";
	}

	// The parser decodes no entity inside <script> or <style>, so their text is written
	// as is; a "<script" or "<style" in it, which could end the element, gets its first
	// letter escaped the way the script or the style reads it back.
	function rawText(name: string, text: string): string {
		let out = "";
		let last = 0;
		let at = text.indexOf("<");
		while (at >= 0) {
			const from = at + 1 < text.length && text.charCodeAt(at + 1) === 47 ? at + 2 : at + 1;
			if (namedAt(text, from, name)) {
				const upper = text.charCodeAt(from) === 83;
				const letter = name === "style" ? (upper ? "\\53 " : "\\73 ") : (upper ? "\\u0053" : "\\u0073");
				out = out + text.slice(last, from) + letter;
				last = from + 1;
			}
			at = text.indexOf("<", at + 1);
		}
		if (last === 0) { return text; }
		return out + text.slice(last);
	}

	function namedAt(text: string, at: int32, name: string): boolean {
		if (at + name.length > text.length) { return false; }
		for (let i = 0; i < name.length; i += 1) {
			if ((text.charCodeAt(at + i) | 32) !== name.charCodeAt(i)) { return false; }
		}
		return true;
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

	function elementMarkup(
		wire: string,
		info: TagInfo,
		names: string[],
		values: string[],
		className: string,
		style: Style | null,
		inner: string,
		childCount: int32,
	): string {
		const tag = info.html;
		let cls = className;
		let scroll = "";
		if (wire === "scrollview") {
			const look = scrollOf(names, values);
			scroll = scrollLookCss(look);
			if (look.hideHorizontal) { cls = cls + " neon-hide-horizontal"; }
			if (look.hideVertical) { cls = cls + " neon-hide-vertical"; }
		}
		let open = "<" + tag;
		if (names.length > 0) {
			const outNames: string[] = [];
			const outValues: string[] = [];
			for (let i = 0; i < names.length; i += 1) {
				const raw = values[i];
				const control = controlAttr(wire, names[i], raw);
				if (control !== null) {
					const written = control as ControlAttr;
					if (written.name !== "") {
						putAttribute(outNames, outValues, written.name, written.value === null ? null : escapeAttribute(written.value as string));
					}
					continue;
				}
				const mapped = domAttrValue(names[i], raw);
				let v = mapped === null ? "" : escapeAttribute(mapped as string);
				if (mapped !== null && names[i] === "class" && cls !== "") { v = v === "" ? cls : v + " " + cls; cls = ""; }
				putAttribute(outNames, outValues, domAttrName(names[i]), mapped === null ? null : v);
			}
			for (let i = 0; i < outNames.length; i += 1) {
				open = open + " " + outNames[i] + "=\"" + outValues[i] + "\"";
			}
		}
		if (cls !== "") { open = open + " class=\"" + cls + "\""; }
		const inline = (style === null ? "" : styleToCss(style as Style)) + scroll;
		if (inline !== "") { open = open + " style=\"" + escapeAttribute(inline) + "\""; }
		if (info.empty) {
			if (childCount > 0) {
				throw new Error("SSR void element '" + tag + "' cannot have children");
			}
			return open + ">";
		}
		if (wire === "multilinetextinput") { return open + ">" + textareaBody(names, values) + "</" + tag + ">"; }
		return open + ">" + inner + "</" + tag + ">";
	}

	// What the markup needs from a wire tag, worked out once per tag.
	class TagInfo {
		html: string;
		baseClass: string;
		rules: WebRule[];
		fixedNames: string[] = [];
		fixedValues: string[] = [];
		empty: boolean;
		marked: boolean;
		raw: string;

		constructor(tag: string) {
			this.html = webHtmlTag(tag);
			this.baseClass = escapeAttribute(baseClassOf(tag));
			this.rules = webRules(tag);
			for (const fixed of webFixedAttrs(tag)) {
				this.fixedNames.push(fixed.name);
				this.fixedValues.push(fixed.value as string);
			}
			this.empty = voidTag(this.html);
			this.marked = !rawTextTag(this.html);
			this.raw = scriptOrStyle(this.html);
		}
	}

	const TAGS = new Map<string, TagInfo>();

	function tagInfo(tag: string): TagInfo {
		const known = TAGS.get(tag);
		if (known !== null) { return known; }
		const info = new TagInfo(tag);
		TAGS.set(tag, info);
		return info;
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

	// ---- The writer: each element becomes markup the moment it is placed ----
	//
	// A NeonNode on the server performs its host calls in document order: an element
	// gets its attributes, then its children, then is placed into its parent. The
	// writer keeps one record per node and, at placement, appends the node's markup to
	// its parent's body; nothing of the tree outlives that call. The two places that
	// put a node somewhere other than at the end of an open element get their own
	// node: the head root collects its children for the head block, and the overlay
	// root drops what a Portal mounts there.

	class SsrNode {
		tag: string;
		text: string = "";
		names: string[] = [];
		values: string[] = [];
		className: string = "";
		style: Style | null = null;
		body: string = "";
		count: int32 = 0;
		info: TagInfo;
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

		constructor(tag: string, info: TagInfo) {
			this.tag = tag;
			this.info = info;
		}
	}

	const PLAIN = new TagInfo("");

	class SsrWrite {
		register: (id: string, css: string) => void;
		head: SsrNode = new SsrNode("head", PLAIN);
		overlay: SsrNode = new SsrNode("overlay", PLAIN);
		headKids: SsrNode[] = [];
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

	function collect(w: SsrWrite, p: SsrNode, n: SsrNode, ref: HostNode | null): void {
		n.parent = p;
		const kids = w.headKids;
		const at = ref === null ? -1 : kids.indexOf(ref as unknown as SsrNode);
		if (at < 0) { kids.push(n); } else { kids.splice(at, 0, n); }
	}

	function writeInto(w: SsrWrite, p: SsrNode, n: SsrNode, ref: HostNode | null): void {
		if (p.drops) { return; }
		if (p.collects) { collect(w, p, n, ref); return; }
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
			if (p.info.marked) {
				if (n.text === "") { p.body += EMPTY_TEXT; p.afterText = false; return; }
				if (p.afterText) { p.body += TEXT_BREAK; }
			}
			p.body += p.info.raw === "" ? escapeText(n.text) : rawText(p.info.raw, n.text);
			p.afterText = true;
			return;
		}
		p.body += elementMarkup(n.tag, n.info, n.names, n.values, n.className, n.style, n.body, n.count);
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
				const info = tagInfo(tag);
				const n = new SsrNode(tag, info);
				for (const rule of info.rules) { w.register(rule.id, rule.css); }
				n.className = info.baseClass;
				for (let i = 0; i < info.fixedNames.length; i += 1) {
					n.names.push(info.fixedNames[i]);
					n.values.push(info.fixedValues[i]);
				}
				return n as unknown as HostNode;
			},
			createText: (s: string): HostNode => {
				const n = new SsrNode("", PLAIN);
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
				n.className = joinClass(joinClass(n.className, LINES_CLASS), escapeAttribute(linesClass(value)));
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
				n.className = joinClass(n.className, escapeAttribute(id));
			},
			addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {},
			append: (parent: HostNode, child: HostNode): void => {
				writeInto(w, parent as unknown as SsrNode, child as unknown as SsrNode, null);
			},
			insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null): void => {
				writeInto(w, parent as unknown as SsrNode, node as unknown as SsrNode, ref);
			},
			removeChild: (parent: HostNode, node: HostNode): void => {
				const p = parent as unknown as SsrNode;
				const n = node as unknown as SsrNode;
				if (p.drops) { return; }
				if (p.collects) {
					const at = w.headKids.indexOf(n);
					if (at >= 0) { w.headKids.splice(at, 1); }
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
					const kids = w.headKids;
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
				return w.headKids.length === 0 ? null : w.headKids[0] as unknown as HostNode;
			},
			cloneNode: null,
			voidArea: null,
			scrollTo: null,
			overlayRoot: (node: HostNode): HostNode => w.overlay as unknown as HostNode,
			headRoot: (node: HostNode): HostNode => w.head as unknown as HostNode,
		};
	}

	function writtenHead(kids: SsrNode[]): string {
		const seen = new Map<string, boolean>();
		let s = "";
		for (const k of kids) {
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
			s = s + elementMarkup(k.tag, k.info, names, values, k.className, k.style, k.body, k.count);
		}
		return s;
	}

	function writeRender(n: NeonNode, w: SsrWrite): SsrMarkup {
		const root = new SsrNode("ssr-root", PLAIN);
		const dispose = asServer((): Dispose => render(n, writerHost(w), root as unknown as HostNode, ""));
		try {
			return { html: root.body, css: "", head: writtenHead(w.headKids) };
		}
		finally {
			w.done = true;
			dispose();
		}
	}

	export function renderToString(n: NeonNode): string {
		return writeRender(n, new SsrWrite(registerCss)).html;
	}

	export function renderToMarkup(n: NeonNode): SsrMarkup {
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
} else {
	import { Node } from "std/meta";

	export macro renderToString(node: Node): Node {
		error("renderToString needs a -d:server build", node);
	}

	export macro renderToMarkup(node: Node): Node {
		error("renderToMarkup needs a -d:server build", node);
	}
}
