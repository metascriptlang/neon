import { domHost } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { createSignal } from "../../src/core/signal";
import { sleepAsync } from "std/core/promise";
import { NeonEvent } from "../../src/render/event";
import { ScrollView, Text, TextInput, View } from "../../src/components/primitives";
import { Modal } from "../../src/components/modal";
import { RefreshControl } from "../../src/components/refreshControl";
import { TouchableOpacity } from "../../src/components/touchable";
import { StatusBar } from "../../src/components/statusBar";
import { ImageBackground } from "../../src/components/imageBackground";

extern class HTMLElement {
	textContent: string;
	tagName: string;
	extern querySelector(selector: cstring): HTMLElement | null;
	extern appendChild(child: HTMLElement): void;
	extern getAttribute(name: cstring): string | null;
}

extern class window {
	static extern eval(code: cstring): string;
}

extern class document {
	static body: HTMLElement;
	static extern createElement(tag: cstring): HTMLElement;
}

function mountPoint(): HTMLElement {
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	return mount;
}

function js(code: string): string {
	return window.eval(`String((() => { ${code} })())`);
}

test "a Modal in Chrome is a fixed dialog over the viewport in body, and Escape requests its close" {
	const [open, setOpen] = createSignal(false);
	let closes = 0;
	const mount = mountPoint();
	render(element(<View><Text>page</Text>
		<Modal visible={open()} animationType="fade" onRequestClose={(): void => { closes += 1; setOpen(false); }}>
			<Text>dialog body</Text>
		</Modal>
	</View>), domHost(), mount as unknown as HostNode);
	assert document.body.querySelector(".neon-modal") === null, "hidden";
	setOpen(true);
	await sleepAsync(50);
	const layer = document.body.querySelector(".neon-modal");
	assert layer !== null && (layer as HTMLElement).textContent === "dialog body", "shown in body";
	assert mount.textContent === "page", "not inside the app mount: " + mount.textContent;
	const box = js("const r = document.querySelector('.neon-modal').getBoundingClientRect(); return `${getComputedStyle(document.querySelector('.neon-modal')).position} ${r.left} ${r.top} ${r.width === innerWidth} ${r.height === innerHeight}`;");
	assert box === "fixed 0 0 true true", "covers the viewport: " + box;
	assert (layer as HTMLElement).getAttribute("aria-modal") === "true", "a modal dialog for assistive tech";
	js("document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); return 1;");
	await sleepAsync(50);
	assert closes === 1 && document.body.querySelector(".neon-modal") === null, "Escape closed it: " + closes.toString();
}

test "a RefreshControl in Chrome shows its indicator while refreshing, in its tint" {
	const [busy, setBusy] = createSignal(false);
	const mount = mountPoint();
	render(element(<ScrollView style={{ height: 200 }} refreshControl={<RefreshControl refreshing={busy()} tintColor="rgb(255, 0, 0)" onRefresh={(): void => {}} />}>
		<View style={{ height: 600 }} />
	</ScrollView>), domHost(), mount as unknown as HostNode);
	await sleepAsync(20);
	const indicator = mount.querySelector(".neon-refresh-indicator");
	assert indicator !== null, "the control mounted an indicator";
	assert js("return getComputedStyle(document.querySelector('.neon-refresh-indicator')).display;") === "none", "idle";
	setBusy(true);
	assert js("const s = getComputedStyle(document.querySelector('.neon-refresh-indicator')); return s.display + ' ' + s.color;") === "block rgb(255, 0, 0)", "refreshing";
	setBusy(false);
}

test "a TouchableOpacity in Chrome fades while the pointer is down and presses on release" {
	let presses = 0;
	const mount = mountPoint();
	render(element(<TouchableOpacity onPress={(e: NeonEvent): void => { presses += 1; }}><Text>fade me</Text></TouchableOpacity>), domHost(), mount as unknown as HostNode);
	const button = mount.querySelector("button");
	assert button !== null, "a button";
	js("document.querySelector('button').dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })); return 1;");
	assert js("return getComputedStyle(document.querySelector('button')).opacity;") === "0.2", "pressed opacity";
	js("document.querySelector('button').dispatchEvent(new PointerEvent('pointerup', { bubbles: true })); return 1;");
	await sleepAsync(250);
	assert presses === 1 && js("return getComputedStyle(document.querySelector('button')).opacity;") === "1", "released";
}

test "a StatusBar takes no space in Chrome and an ImageBackground stretches its image under the content" {
	const mount = mountPoint();
	render(element(<View>
		<StatusBar barStyle="dark-content" />
		<ImageBackground source={{ uri: "data:image/gif;base64,R0lGODlhAQABAAAAACw=" }} style={{ width: 120, height: 80 }}><Text>over</Text></ImageBackground>
	</View>), domHost(), mount as unknown as HostNode);
	await sleepAsync(20);
	const sizes = js("const box = document.querySelector('img').parentElement.getBoundingClientRect(); const img = document.querySelector('img').getBoundingClientRect(); return `${img.width}x${img.height} ${img.left === box.left && img.top === box.top}`;");
	assert sizes === "120x80 true", "the image fills the box: " + sizes;
	assert js("return document.querySelector('statusbar') === null || getComputedStyle(document.querySelector('statusbar')).display;") === "none", "no status bar box";
}

test "Text numberOfLines clamps in Chrome and selectable={false} turns selection off" {
	const [lines, setLines] = createSignal(2);
	const mount = mountPoint();
	render(element(<View style={{ width: 120 }}>
		<Text numberOfLines={lines()} selectable={false} style={{ fontSize: 16 }}>one two three four five six seven eight nine ten eleven twelve thirteen fourteen</Text>
	</View>), domHost(), mount as unknown as HostNode);
	await sleepAsync(20);
	const clamped = js("const s = document.querySelector('.neon-lines'); const lh = parseFloat(getComputedStyle(s).lineHeight) || 16 * 1.2; return `${Math.round(s.getBoundingClientRect().height / lh)} ${getComputedStyle(s).userSelect}`;");
	assert clamped === "2 none", "two lines, no selection: " + clamped;
	setLines(0);
	assert js("return document.querySelector('.neon-lines') === null;") === "true", "0 lifts the clamp";
}

test "a multiline TextInput is a textarea in Chrome whose input reaches onChangeText" {
	let typed = "";
	const mount = mountPoint();
	render(element(<View><TextInput multiline={true} accessibilityLabel="Notes" onChangeText={(t: string): void => { typed = t; }} /></View>), domHost(), mount as unknown as HostNode);
	assert mount.querySelector("textarea") !== null, "a textarea";
	js("const el = document.querySelector('textarea'); el.value = 'a\\nb'; el.dispatchEvent(new Event('input', { bubbles: true })); return 1;");
	assert typed === "a\nb", "typed: " + typed;
}
