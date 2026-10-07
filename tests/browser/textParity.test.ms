// RN Text in Chrome: nested Text is an inline span with its own style, textAlign reaches
// the element, and a Text (or a nested span) with onPress takes the click.

import { domHost } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { Text, View, TextInput, TextSelection } from "../../src/components/primitives";
import { createSignal } from "../../src/core/signal";
import { sleepAsync } from "std/core/promise";

extern class HTMLElement {
	extern appendChild(child: HTMLElement): void;
	extern setAttribute(name: cstring, value: cstring): void;
}

extern class window {
	static extern eval(code: cstring): string;
}

extern class document {
	static body: HTMLElement;
	static extern createElement(tag: cstring): HTMLElement;
}

function mountPoint(id: string): HTMLElement {
	const mount = document.createElement("div");
	mount.setAttribute("id", id);
	document.body.appendChild(mount);
	return mount;
}

function js(code: string): string {
	return window.eval(`String((() => { ${code} })())`);
}

function computed(selector: string, fields: string): string {
	return js(`const s = getComputedStyle(document.querySelector('${selector}')); return [${fields}].map((f) => s[f]).join(' ');`);
}

test "a nested Text in Chrome is an inline span styled over its parent's text" {
	const mount = mountPoint("nested-one");
	render(element(<View>
		<Text style={{ color: "#112233", fontSize: 15 }}>Hi <Text style={{ fontWeight: "bold", color: "#ff0000" }}>Ada</Text>, <Text style={{ fontStyle: "italic", textDecorationLine: "underline" }}>see</Text>.</Text>
	</View>), domHost(), mount as unknown as HostNode);
	const text = js("return document.querySelector('#nested-one > div > span').textContent;");
	const outer = computed("#nested-one > div > span", "'color', 'fontSize'");
	const bold = computed("#nested-one > div > span > span:nth-of-type(1)", "'display', 'color', 'fontSize', 'fontWeight'");
	const italic = computed("#nested-one > div > span > span:nth-of-type(2)", "'fontStyle', 'textDecorationLine', 'color'");
	const lines = js("const r = document.querySelector('#nested-one > div > span').getClientRects(); return r.length;");
	assert text === "Hi Ada, see.", "one run of text: " + text;
	assert outer === "rgb(17, 34, 51) 15px", "outer: " + outer;
	assert bold === "inline rgb(255, 0, 0) 15px 700", "the span keeps the outer size and sets its weight and colour: " + bold;
	assert italic === "italic underline rgb(17, 34, 51)", "the span inherits the outer colour: " + italic;
	assert lines === "1", "the spans flow on one line: " + lines;
}

test "textAlign in Chrome centres a Text across its parent" {
	const mount = mountPoint("align-one");
	render(element(<View style={{ width: 300 }}>
		<Text style={{ textAlign: "center" }}>mid</Text>
		<Text style={{ textAlign: "justify" }}>wide</Text>
	</View>), domHost(), mount as unknown as HostNode);
	const centred = computed("#align-one > div > span:nth-of-type(1)", "'textAlign', 'width'");
	const justified = computed("#align-one > div > span:nth-of-type(2)", "'textAlign'");
	assert centred === "center 300px", "centred across the parent: " + centred;
	assert justified === "justify", "justify: " + justified;
}

test "a Text with onPress in Chrome takes the click, and so does a pressable nested span" {
	const mount = mountPoint("press-one");
	let log = "";
	render(element(<View>
		<Text onPress={(): void => { log += "text;"; }}>Read <Text onPress={(): void => { log += "terms;"; }} style={{ textDecorationLine: "underline" }}>terms</Text></Text>
	</View>), domHost(), mount as unknown as HostNode);
	js("document.querySelector('#press-one > div > span > span').click(); return '';");
	const afterSpan = log;
	log = "";
	js("document.querySelector('#press-one > div > span').click(); return '';");
	assert afterSpan.indexOf("terms;") === 0, "the span's own press fires first: " + afterSpan;
	assert log === "text;", "the outer text's press: " + log;
}

test "a multiline TextInput in Chrome grows with its text up to maxHeight" {
	const mount = mountPoint("grow-one");
	const [notes, setNotes] = createSignal("");
	render(element(<View style={{ width: 200 }}>
		<TextInput multiline={true} value={notes()} style={{ maxHeight: 80, fontSize: 16, padding: 0, borderWidth: 0 }} />
	</View>), domHost(), mount as unknown as HostNode);
	const height = (): number => parseFloat(js("return document.querySelector('#grow-one textarea').getBoundingClientRect().height;"));
	const empty = height();
	setNotes("one\ntwo\nthree");
	const three = height();
	setNotes("1\n2\n3\n4\n5\n6\n7\n8\n9");
	const capped = height();
	assert empty > 0 && three > empty * 2, `grows: ${empty} ${three}`;
	assert capped === 80, "capped by maxHeight: " + capped.toString();
}

test "a TextInput in Chrome sets its selection and reports the user's" {
	const mount = mountPoint("select-one");
	let seen = "";
	render(element(<View>
		<TextInput value="hello" selection={{ start: 1, end: 3 }} onSelectionChange={(s: TextSelection): void => { seen = `${s.start}-${s.end}`; }} />
	</View>), domHost(), mount as unknown as HostNode);
	const written = js("const el = document.querySelector('#select-one input'); return el.selectionStart + ',' + el.selectionEnd;");
	js("const el = document.querySelector('#select-one input'); el.focus(); el.setSelectionRange(2, 5); return '';");
	await sleepAsync(50);
	assert written === "1,3", "written: " + written;
	assert seen === "2-5", "reported: " + seen;
}
