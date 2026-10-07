import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { Style, emptyStyle, setStyleField } from "../../src/render/style";
import { NeonEvent } from "../../src/render/event";
import { bindAttr } from "../../src/render/host";
import { createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { HOST_MOVE_CONTRACT, RECONCILE_CONTRACT, HOST_ATTR_CONTRACT, hostMoveContract, reconcileContract, hostAttrContract } from "../render/hostContract";
import { sleepAsync } from "std/core/promise";
import { useWindowDimensions, useColorScheme } from "../../src/render/environment";

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
	fontStyle: string;
	textDecorationLine: string;
}

extern class ProbeClassList {
	extern contains(name: cstring): boolean;
}

extern class ProbeAttr {
	name: string;
	value: string;
}

extern class ProbeAttrs {
	length: number;
	extern item(i: number): ProbeAttr;
}

extern class Node {
	attributes: ProbeAttrs;
	textContent: string;
	tagName: string;
	value: string;
	checked: boolean;
	style: ProbeStyle;
	classList: ProbeClassList;
	extern getAttribute(name: cstring): string | null;
	extern click(): void;
	extern remove(): void;
}

function probe(n: HostNode): Node {
	return n as unknown as Node;
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

test "fontStyle and textDecorationLine reach the element" {
	const h = domHost();
	const el = mount("view");
	h.setStyle(el, styleWith("fontStyle", "italic"));
	assert probe(el).style.fontStyle === "italic", "fontStyle is in the IR and the browser projects it";
	h.setStyle(el, styleWith("textDecorationLine", "underline"));
	assert probe(el).style.textDecorationLine === "underline", "textDecorationLine is in the IR and the browser projects it";
	probe(el).remove();
}

test "the DOM defines the host move contract" {
	const got = hostMoveContract(domHost());
	assert got === HOST_MOVE_CONTRACT, got;
}

test "reconcileArrays keeps its contract on the DOM" {
	const got = reconcileContract(domHost());
	assert got === RECONCILE_CONTRACT, got;
}


function domAttrs(n: HostNode): string {
	const list = probe(n).attributes;
	let out = "";
	for (let i = 0; i < list.length; i += 1) {
		const hostBase = list.item(i).name === "class" && list.item(i).value === "neon-view";
		if (!hostBase) { out = out + (out === "" ? "" : ",") + list.item(i).name + "=" + list.item(i).value; }
	}
	return out === "" ? "_" : out;
}

test "the DOM host keeps its own attribute contract" {
	const got = hostAttrContract(domHost(), domAttrs);
	assert got === HOST_ATTR_CONTRACT, got;
}

test "removing value clears a controlled input the user typed into" {
	const h = domHost();
	const el = mount("textinput");
	h.setAttr(el, "value", "first");
	probe(el).value = "typed by user";
	h.removeAttr(el, "value");
	assert probe(el).value === "", "the field empties like Solid's value = null";
	assert probe(el).getAttribute("value") === null, "the attribute is gone too";
	probe(el).remove();
}

test "a bound value that turns null empties the input" {
	const h = domHost();
	const el = mount("textinput");
	const [v, setV] = createSignal<string | null>("a");
	createRoot(() => { bindAttr(h, el, "value", () => v()); });
	probe(el).value = "typed by user";
	setV(null);
	assert probe(el).value === "", "null clears the field";
	setV("b");
	assert probe(el).value === "b", "a later value writes again";
	probe(el).remove();
}

extern class window {
	static extern eval(code: cstring): void;
}

test "a real KeyboardEvent reaches the handler with React Native's key fields" {
	const h = domHost();
	const el = mount("view");
	h.setAttr(el, "id", "neon-key-probe");
	let seen = "";
	h.addEvent(el, "onKeyDown", (e: NeonEvent): void => {
		seen = `${e.type} ${e.key} ${e.code} alt=${e.altKey} ctrl=${e.ctrlKey} meta=${e.metaKey} shift=${e.shiftKey} repeat=${e.repeat} composing=${e.isComposing}`;
	});
	window.eval("document.getElementById('neon-key-probe').dispatchEvent(new KeyboardEvent('keydown', { key: 'A', code: 'KeyA', shiftKey: true, ctrlKey: true, repeat: true, isComposing: true }))");
	assert seen === "keydown A KeyA alt=false ctrl=true meta=false shift=true repeat=true composing=true", "fields: " + seen;
	probe(el).remove();
}

test "onLayout reports the frame relative to the parent, and again when it changes" {
	const h = domHost();
	const outer = mount("view");
	h.setStyle(outer, styleWith("paddingTop", 10));
	const el = h.createElement("view");
	h.setStyle(el, styleWith("height", 40));
	h.insertBefore(outer, el, null);
	let got = "";
	h.addEvent(el, "onLayout", (e: NeonEvent): void => { got += `${e.type} ${e.y} ${e.height};`; });
	await sleepAsync(100);
	assert got === "layout 10 40;", "after mount: " + got;
	h.setStyle(el, styleWith("height", 60));
	await sleepAsync(100);
	assert got === "layout 10 40;layout 10 60;", "after a resize: " + got;
	probe(outer).remove();
}

test "onLayout keeps logical parent coordinates and dimensions under inversions and scale" {
	const h = domHost();
	const outer = mount("view");
	h.setStyle(outer, { paddingTop: 10, transform: "scaleY(-1)" });
	const el = h.createElement("view");
	h.setStyle(el, { height: 40, width: 80, transform: "scale(2)" });
	h.insertBefore(outer, el, null);
	let got = "";
	h.addEvent(el, "onLayout", (e: NeonEvent): void => { got = `${e.x} ${e.y} ${e.width} ${e.height}`; });
	await sleepAsync(100);
	assert got === "0 10 80 40", "logical frame, not the transformed bounding rectangle: " + got;
	probe(outer).remove();
}

test "onLayout follows a retained node moved between siblings without resizing it" {
	const h = domHost();
	const outer = mount("view");
	h.setStyle(outer, { height: 40 });
	const first = h.createElement("view");
	const second = h.createElement("view");
	h.setStyle(first, { height: 20 });
	h.setStyle(second, { height: 20 });
	h.insertBefore(outer, first, null);
	h.insertBefore(outer, second, null);
	let positions = "";
	h.addEvent(second, "onLayout", (e: NeonEvent): void => { positions += `${e.y};`; });
	await sleepAsync(100);
	assert positions === "20;", positions;
	h.insertBefore(outer, second, first);
	await sleepAsync(100);
	assert positions === "20;0;", "same node and size, new logical position: " + positions;
	probe(outer).remove();
}

test "RN TextInput and accessibility props map onto input and ARIA attributes" {
	const h = domHost();
	const el = mount("textinput");
	h.setAttr(el, "placeholder", "Email");
	h.setAttr(el, "keyboardType", "email-address");
	h.setAttr(el, "returnKeyType", "next");
	h.setAttr(el, "secureTextEntry", "true");
	h.setAttr(el, "editable", "false");
	h.setAttr(el, "maxLength", "12");
	h.setAttr(el, "accessibilityLabel", "Email address");
	h.setAttr(el, "accessibilityRole", "search");
	const got = `${probe(el).getAttribute("placeholder")} ${probe(el).getAttribute("inputmode")} ${probe(el).getAttribute("enterkeyhint")} ${probe(el).getAttribute("type")} ${probe(el).getAttribute("readonly") !== null} ${probe(el).getAttribute("maxlength")} ${probe(el).getAttribute("aria-label")} ${probe(el).getAttribute("role")}`;
	assert got === "Email email next password true 12 Email address search", "attributes: " + got;
	h.removeAttr(el, "accessibilityLabel");
	assert probe(el).getAttribute("aria-label") === null, "removing the RN name removes the ARIA attribute";
	h.setAttr(el, "editable", "true");
	assert probe(el).getAttribute("readonly") === null, "editable again";
	probe(el).remove();
	const header = mount("text");
	h.setAttr(header, "accessibilityRole", "header");
	assert probe(header).getAttribute("role") === "heading", "header becomes an ARIA heading";
	probe(header).remove();
}

test "Enter submits a TextInput with its value, and the focus capability moves the DOM focus" {
	const h = domHost();
	const el = mount("textinput");
	h.setAttr(el, "id", "neon-submit-probe");
	let seen = "";
	h.addEvent(el, "onSubmitEditing", (e: NeonEvent): void => { seen += `${e.type} ${e.value};`; });
	h.addEvent(el, "onFocus", (e: NeonEvent): void => { seen += "focus;"; });
	h.addEvent(el, "onBlur", (e: NeonEvent): void => { seen += "blur;"; });
	probe(el).value = "neon";
	window.eval("document.getElementById('neon-submit-probe').dispatchEvent(new KeyboardEvent('keydown', { key: 'a' }))");
	window.eval("document.getElementById('neon-submit-probe').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }))");
	const focus = h.focus;
	assert focus !== null, "the browser host advertises focus";
	if (focus !== null) {
		focus(el, true);
		focus(el, false);
	}
	assert seen === "submitediting neon;focus;blur;", "events: " + seen;
	probe(el).remove();
}

test "Switch is a role=switch checkbox whose change reports the new value and then returns to the controlled one" {
	const h = domHost();
	const el = mount("switch");
	h.setAttr(el, "id", "neon-switch-probe");
	h.setAttr(el, "value", "false");
	let seen = "";
	h.addEvent(el, "onValueChange", (e: NeonEvent): void => { seen += `${e.type} ${e.value};`; });
	probe(el).click();
	const shape = `${probe(el).tagName} ${probe(el).getAttribute("type")} ${probe(el).getAttribute("role")}`;
	assert shape === "INPUT checkbox switch", "shape: " + shape;
	assert seen === "valuechange true;", "event: " + seen;
	assert !probe(el).checked, "an unchanged value prop pulls the checkbox back";
	h.setAttr(el, "value", "true");
	assert probe(el).checked, "a new value prop checks it";
	probe(el).remove();
}

test "ActivityIndicator and Image map onto a spinner element and an img with load and error events" {
	const h = domHost();
	const spinner = mount("activityindicator");
	h.setAttr(spinner, "animating", "false");
	assert probe(spinner).getAttribute("data-animating") === "false", "animating attribute";
	probe(spinner).remove();
	const img = mount("image");
	const [seen, setSeen] = createSignal("");
	h.addEvent(img, "onLoad", (e: NeonEvent): void => { setSeen(seen() + `load ${e.width}x${e.height};`); });
	h.addEvent(img, "onError", (e: NeonEvent): void => { setSeen(seen() + "error;"); });
	h.setAttr(img, "resizeMode", "contain");
	h.setAttr(img, "source", "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7");
	await sleepAsync(200);
	h.setAttr(img, "source", "data:image/png;base64,bm90IGFuIGltYWdl");
	await sleepAsync(200);
	assert `${probe(img).tagName} ${probe(img).getAttribute("data-resize")}` === "IMG contain", "img shape";
	assert seen() === "load 1x1;error;", "events: " + seen();
	probe(img).remove();
}

test "the DOM host publishes the window size and the preferred color scheme" {
	const h = domHost();
	const dims = useWindowDimensions();
	const scheme = useColorScheme();
	assert dims().width > 0 && dims().height > 0, "window size published: " + `${dims().width}x${dims().height}`;
	assert scheme() === "light" || scheme() === "dark", "a scheme is published";
}
