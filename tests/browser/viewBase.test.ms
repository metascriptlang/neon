// A View in Chrome lays out the way it does on a phone: React Native Web's
// View base style (`styles.view$raw` in react-native-web exports/View) carried
// by one zero-specificity class, so an author style always wins.

import { domHost } from "../../src/platform/browser/dom";
import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { sleepAsync } from "std/core/promise";
import { NeonEvent } from "../../src/render/event";
import { For } from "../../src/macros/ui/flow";
import { Accessor } from "../../src/core/signal";
import { ScrollView, Text, View, Pressable } from "../../src/components/primitives";

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

const sheet = createStyles({
	row: { flexDirection: "row", position: "absolute" },
});

test "a View in Chrome is a positioned flex column that can shrink below its content" {
	const mount = mountPoint("base-one");
	render(element(<View />), domHost(), mount as unknown as HostNode);
	const got = computed("#base-one > div", "'display', 'flexDirection', 'position', 'minHeight', 'minWidth', 'flexShrink', 'flexBasis', 'boxSizing', 'alignItems', 'zIndex', 'marginTop', 'paddingTop', 'borderTopStyle', 'borderTopWidth'");
	assert got === "flex column relative 0px 0px 0 auto border-box stretch 0 0px 0px solid 0px", "RN-web view$raw: " + got;
}

test "an author style wins over the View base, inline and from a sheet class" {
	const mount = mountPoint("base-author");
	render(element(<View>
		<View style={{ flexDirection: "row", flexShrink: 1, position: "absolute" }} />
		<View style={sheet.row} />
	</View>), domHost(), mount as unknown as HostNode);
	const inline = computed("#base-author > div > div:nth-child(1)", "'flexDirection', 'flexShrink', 'position'");
	assert inline === "row 1 absolute", "inline: " + inline;
	const sheetRule = computed("#base-author > div > div:nth-child(2)", "'flexDirection', 'position'");
	assert sheetRule === "row absolute", "sheet class: " + sheetRule;
}

test "a list under two flex 1 Views scrolls inside its screen instead of growing to its content" {
	const mount = mountPoint("base-list");
	const rows: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19];
	render(element(<View style={{ height: 200 }}>
		<View style={{ flex: 1 }}>
			<View style={{ flex: 1 }}>
				<ScrollView><For each={rows}>{(n: number, i: Accessor<number>): NeonNode => <View style={{ height: 50 }} />}</For></ScrollView>
			</View>
		</View>
	</View>), domHost(), mount as unknown as HostNode);
	const got = js("const s = document.querySelector('#base-list .neon-scrollview'); return `${s.clientHeight} ${s.scrollHeight}`;");
	assert got === "200 1000", "viewport and content: " + got;
}

test "an absolute child stays inside its View instead of escaping to the page" {
	const mount = mountPoint("base-abs");
	render(element(<View style={{ marginTop: 40, height: 100 }}>
		<View style={{ position: "absolute", top: 10, left: 0, width: 20, height: 20 }} />
	</View>), domHost(), mount as unknown as HostNode);
	const got = js("const p = document.querySelector('#base-abs > div'); const c = p.firstElementChild; return `${c.getBoundingClientRect().top - p.getBoundingClientRect().top}`;");
	assert got === "10", "child offset from its parent: " + got;
}

test "a View border needs only a width, as on a phone" {
	const mount = mountPoint("base-border");
	render(element(<View style={{ width: 50, height: 50, borderWidth: 2, padding: 4 }} />), domHost(), mount as unknown as HostNode);
	const got = js("const v = document.querySelector('#base-border > div'); const s = getComputedStyle(v); return `${s.borderTopStyle} ${s.borderTopColor} ${v.offsetWidth}`;");
	assert got === "solid rgb(0, 0, 0) 50", "border-box with a solid black border: " + got;
}

test "a Pressable in Chrome is a View, and a Text keeps its newlines and the colour around it" {
	const mount = mountPoint("base-press");
	render(element(<View style={{ color: "red" }}>
		<Pressable onPress={(e: NeonEvent): void => {}}><Text>{"one\ntwo"}</Text></Pressable>
	</View>), domHost(), mount as unknown as HostNode);
	const press = computed("#base-press button", "'display', 'flexDirection', 'backgroundColor', 'paddingTop', 'borderTopWidth', 'textAlign'");
	assert press === "flex column rgba(0, 0, 0, 0) 0px 0px start", "pressable: " + press;
	const text = computed("#base-press span", "'whiteSpace', 'boxSizing', 'position', 'marginTop', 'color'");
	assert text === "pre-wrap border-box relative 0px rgb(255, 0, 0)", "text: " + text;
}

test "a class prop keeps the View base" {
	const mount = mountPoint("base-class");
	render(element(<View class="mine" />), domHost(), mount as unknown as HostNode);
	await sleepAsync(0);
	const got = js("const v = document.querySelector('#base-class > div'); return `${v.classList.contains('mine')} ${getComputedStyle(v).display}`;");
	assert got === "true flex", "class and base: " + got;
}
