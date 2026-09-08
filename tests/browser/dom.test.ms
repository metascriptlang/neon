import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { Style, emptyStyle, setStyleField } from "../../src/render/style";
import { NeonEvent } from "../../src/render/event";
import { bindAttr } from "../../src/render/host";
import { createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";

extern class ProbeStyle {
	backgroundColor: string;
	color: string;
	width: string;
	height: string;
	padding: string;
	paddingTop: string;
	paddingLeft: string;
	flex: string;
	flexGrow: string;
	flexShrink: string;
	minWidth: string;
	marginTop: string;
	fontSize: string;
	fontWeight: string;
	textAlign: string;
	overflow: string;
}

extern class ProbeClassList {
	extern contains(name: cstring): boolean;
}

extern class ProbeNode {
	textContent: string;
	tagName: string;
	value: string;
	style: ProbeStyle;
	classList: ProbeClassList;
	extern getAttribute(name: cstring): cstring | null;
	extern click(): void;
	extern remove(): void;
}

function probe(n: HostNode): ProbeNode {
	return n as unknown as ProbeNode;
}

function styleWith(name: string, v: number | string | null): Style {
	const s = emptyStyle();
	setStyleField(s, name, v);
	return s;
}

function mount(tag: string): HostNode {
	const h = domHost();
	const el = h.createElement(tag);
	h.insertBefore(documentBody(), el, null);
	return el;
}

test "createElement + insertBefore puts a live node in the document" {
	const el = mount("view");
	assert probe(el).tagName === "DIV", "the view wire tag maps to div";
	probe(el).remove();
}

test "createText + setText writes textContent" {
	const h = domHost();
	const t = h.createText("hello");
	h.setText(t, "world");
	assert probe(t).textContent === "world", "setText replaces the text";
}

test "setAttr reaches getAttribute" {
	const h = domHost();
	const el = mount("view");
	h.setAttr(el, "data-neon", "yes");
	assert probe(el).getAttribute("data-neon") === "yes", "attribute is readable back";
	probe(el).remove();
}

test "setStyle writes a supported field onto the element" {
	const h = domHost();
	const el = mount("view");
	h.setStyle(el, styleWith("backgroundColor", "rgb(1, 2, 3)"));
	assert probe(el).style.backgroundColor === "rgb(1, 2, 3)", "backgroundColor lands";
	probe(el).remove();
}

test "setStyle projects a bare number as px" {
	const h = domHost();
	const el = mount("view");
	h.setStyle(el, styleWith("width", 120));
	assert probe(el).style.width === "120px", "120 becomes 120px";
	probe(el).remove();
}

test "setStyleClass adds the class — the channel mockHost cannot see" {
	const h = domHost();
	const el = mount("view");
	const put = h.setStyleClass;
	assert put !== null, "the browser host advertises a stylesheet";
	if (put !== null) { put(el, "neon-probe-cls", ".neon-probe-cls{color:rgb(9,9,9)}"); }
	assert probe(el).classList.contains("neon-probe-cls"), "class is on the node";
	probe(el).remove();
}

test "addEvent: a click reaches the handler as a neon press event" {
	const h = domHost();
	const el = mount("pressable");
	let seen = 0;
	let evType = "";
	h.addEvent(el, "onPress", (e: NeonEvent): void => {
		seen = seen + 1;
		evType = e.type;
	});
	probe(el).click();
	assert seen === 1, "handler ran exactly once";
	assert evType === "press", "event keeps the neon spelling";
	probe(el).remove();
}

test "setStyleProp writes one field without clearing the rest" {
	const h = domHost();
	const el = mount("view");
	h.setStyle(el, styleWith("backgroundColor", "rgb(4, 5, 6)"));
	const one = h.setStyleProp;
	assert one !== null, "the browser host advertises a partial write";
	if (one !== null) { one(el, "color", "rgb(7, 8, 9)"); }
	assert probe(el).style.color === "rgb(7, 8, 9)", "the written field lands";
	assert probe(el).style.backgroundColor === "rgb(4, 5, 6)", "the untouched field survives";
	probe(el).remove();
}


// The Style IR carries 45 CSS fields. Before 2026-09-07 the browser extern had a
// slot for 21 of them and applyCss wrote 21; the rest vanished into `_ => {}`.
// applyCss now routes every field through applyCssProp, so the static and
// per-property paths share one table and cannot drift.

test "flex reaches the element" {
	const h = domHost();
	const el = mount("view");
	h.setStyle(el, styleWith("flex", 1));
	assert probe(el).style.flexGrow === "1", "flex expands to a grow factor";
	probe(el).remove();
}

test "paddingTop reaches the element" {
	const h = domHost();
	const el = mount("view");
	h.setStyle(el, styleWith("paddingTop", 12));
	assert probe(el).style.paddingTop === "12px", "per-side padding";
	probe(el).remove();
}

test "minWidth reaches the element" {
	const h = domHost();
	const el = mount("view");
	h.setStyle(el, styleWith("minWidth", 80));
	assert probe(el).style.minWidth === "80px", "min/max sizing";
	probe(el).remove();
}

test "fontSize lands on both the static and the per-property path" {
	const h = domHost();
	const stat = mount("view");
	h.setStyle(stat, styleWith("fontSize", 20));
	assert probe(stat).style.fontSize === "20px", "static path carries fontSize";
	const dyn = mount("view");
	const one = h.setStyleProp;
	if (one !== null) { one(dyn, "fontSize", 20); }
	assert probe(dyn).style.fontSize === "20px", "a signal-driven fontSize lands too";
	probe(stat).remove();
	probe(dyn).remove();
}

test "a shorthand is not clobbered by the longhands applyCss writes after it" {
	const h = domHost();
	const el = mount("view");
	h.setStyle(el, styleWith("flex", 1));
	assert probe(el).style.flexGrow === "1", "flexGrow survives";
	assert probe(el).style.flexShrink === "1", "flexShrink survives";
	probe(el).remove();
}

test "a longhand set alongside its shorthand wins" {
	const h = domHost();
	const el = mount("view");
	const s = emptyStyle();
	setStyleField(s, "padding", 4);
	setStyleField(s, "paddingTop", 20);
	h.setStyle(el, s);
	assert probe(el).style.paddingTop === "20px", "the more specific field is applied last";
	assert probe(el).style.paddingLeft === "4px", "the shorthand still covers the other sides";
	probe(el).remove();
}

test "setStyle clears a field that is no longer set" {
	const h = domHost();
	const el = mount("view");
	h.setStyle(el, styleWith("minWidth", 80));
	assert probe(el).style.minWidth === "80px", "first apply sets it";
	h.setStyle(el, styleWith("paddingTop", 1));
	assert probe(el).style.minWidth === "", "a re-apply drops what the new Style omits";
	probe(el).remove();
}

test "a controlled input is steered after the user types" {
	const h = domHost();
	const el = mount("textinput");
	h.setAttr(el, "value", "first");
	assert probe(el).value === "first", "the attribute seeds the field";
	probe(el).value = "typed by user";
	h.setAttr(el, "value", "second");
	assert probe(el).value === "second", "the host must write the property, not the attribute";
	probe(el).remove();
}

test "a bound value steers the input through the reactive path too" {
	const h = domHost();
	const el = mount("textinput");
	const [v, setV] = createSignal("a");
	createRoot(() => { bindAttr(h, el, "value", () => v()); });
	assert probe(el).value === "a", "the bind seeds the field";
	probe(el).value = "typed by user";
	setV("b");
	assert probe(el).value === "b", "a changed signal overwrites what the user typed";
	probe(el).remove();
}

test "overflow reaches the element" {
	const h = domHost();
	const el = mount("view");
	h.setStyle(el, styleWith("overflow", "hidden"));
	assert probe(el).style.overflow === "hidden", "overflow is in the IR and the browser projects it";
	probe(el).remove();
}

