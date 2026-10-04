import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { ScrollView, ScrollViewHandle, View, Pressable, KeyboardShouldPersistTaps, KeyboardDismissMode } from "../../src/components/primitives";
import { sleepAsync } from "std/core/promise";
import { createSignal } from "../../src/core/signal";

extern class HTMLElement {
	tagName: string;
	scrollTop: number;
	scrollLeft: number;
	scrollWidth: number;
	clientWidth: number;
	scrollHeight: number;
	clientHeight: number;
	firstChild: HTMLElement;
	extern remove(): void;
	extern setAttribute(name: cstring, value: cstring): void;
	extern getAttribute(name: cstring): string;
}


extern class window {
	static extern eval(code: cstring): void;
}
function probe(n: HostNode): HTMLElement {
	return n as unknown as HTMLElement;
}

function rows(): NeonNode {
	return element(<View>
		<View style={{ height: 50 }} /><View style={{ height: 50 }} /><View style={{ height: 50 }} /><View style={{ height: 50 }} />
		<View style={{ height: 50 }} /><View style={{ height: 50 }} /><View style={{ height: 50 }} /><View style={{ height: 50 }} />
	</View>);
}

test "ScrollView is a div that scrolls its own overflow" {
	const handles: ScrollViewHandle[] = [];
	render(element(<ScrollView style={{ height: 100 }} ref={(x: ScrollViewHandle): void => { handles.push(x); }}>{rows()}</ScrollView>), domHost(), documentBody());
	const el = probe(handles[0].node);
	assert el.tagName === "DIV", "tag " + el.tagName;
	assert el.clientHeight === 100, "viewport " + el.clientHeight.toString();
	assert el.scrollHeight === 400, "content " + el.scrollHeight.toString();
	el.scrollTop = 30;
	assert el.scrollTop === 30, "the div scrolls: " + el.scrollTop.toString();
	el.remove();
}

test "scrollTo moves the content offset" {
	const handles: ScrollViewHandle[] = [];
	render(element(<ScrollView style={{ height: 100 }} ref={(x: ScrollViewHandle): void => { handles.push(x); }}>{rows()}</ScrollView>), domHost(), documentBody());
	handles[0].scrollTo({ y: 120, animated: false });
	assert probe(handles[0].node).scrollTop === 120, "offset " + probe(handles[0].node).scrollTop.toString();
	probe(handles[0].node).remove();
}

test "onScroll reports React Native's offset, viewport and content size" {
	const handles: ScrollViewHandle[] = [];
	let got = "";
	render(element(<ScrollView style={{ height: 100, width: 200 }} ref={(x: ScrollViewHandle): void => { handles.push(x); }} onScroll={(e: NeonEvent): void => {
		got = `${e.type} ${e.y} ${e.width} ${e.height} ${e.contentHeight}`;
	}}>{rows()}</ScrollView>), domHost(), documentBody());
	handles[0].scrollTo({ y: 120, animated: false });
	await sleepAsync(100);
	assert got === "scroll 120 200 100 400", "payload: " + got;
	probe(handles[0].node).remove();
}

test "horizontal overflow measures on x and scrollTo clamps to its content tail" {
	const handles: ScrollViewHandle[] = [];
	const dispose = render(element(<ScrollView horizontal={true} style={{ width: 200, height: 100 }}
		ref={(h: ScrollViewHandle): void => { handles.push(h); }}>
		<View style={{ width: 150, height: 100, flexShrink: 0 }} />
		<View style={{ width: 150, height: 100, flexShrink: 0 }} />
		<View style={{ width: 150, height: 100, flexShrink: 0 }} />
	</ScrollView>), domHost(), documentBody());
	const el = probe(handles[0].node);
	assert el.scrollWidth === 450 && el.clientWidth === 200, "three horizontal children fill a 450-wide content row";
	handles[0].scrollTo({ x: 1000, animated: false });
	assert el.scrollLeft === 250, "native DOM offset clamps to the final 250-point tail";
	dispose();
}

test "browser paging settles to viewport intervals and emits one final momentum boundary" {
	const handles: ScrollViewHandle[] = [];
	let ended = -1.0;
	const dispose = render(element(<ScrollView pagingEnabled={true} style={{ height: 100 }}
		ref={(h: ScrollViewHandle): void => { handles.push(h); }}
		onMomentumScrollEnd={(e: NeonEvent): void => { ended = e.y; }}>{rows()}</ScrollView>), domHost(), documentBody());
	handles[0].scrollTo({ y: 151, animated: false });
	await sleepAsync(400);
	assert probe(handles[0].node).scrollTop === 200 && ended === 200, "paging reaches the next viewport, not a child-size snap: " + ended.toString();
	dispose();
}

test "browser pull-to-refresh respects its threshold and controlled refreshing completion" {
	const [refreshing, setRefreshing] = createSignal(false);
	const handles: ScrollViewHandle[] = [];
	let calls = 0;
	const dispose = render(element(<ScrollView refreshing={refreshing()} style={{ height: 100 }}
		ref={(h: ScrollViewHandle): void => { handles.push(h); }}
		onRefresh={(): void => { calls += 1; setRefreshing(true); }}>{rows()}</ScrollView>), domHost(), documentBody());
	probe(handles[0].node).setAttribute("id", "neon-refresh-probe");
	window.eval("window.neonPull = y => { const el = document.getElementById('neon-refresh-probe'); const touch = n => new Touch({identifier: 1, target: el, clientX: 0, clientY: n}); el.dispatchEvent(new TouchEvent('touchstart', {touches: [touch(0)], cancelable: true})); el.dispatchEvent(new TouchEvent('touchmove', {touches: [touch(y)], cancelable: true})); el.dispatchEvent(new TouchEvent('touchend', {touches: [], cancelable: true})); }; window.neonPull(63);");
	assert calls === 0, "a below-threshold pull does not request refresh";
	window.eval("window.neonPull(64); window.neonPull(100);");
	assert calls === 1 && refreshing(), "controlled refresh permits one request while active";
	setRefreshing(false);
	window.eval("window.neonPull(64); delete window.neonPull;");
	assert calls === 2, "completion rearms the next pull";
	dispose();
}

function tapMode(index: int32): KeyboardShouldPersistTaps {
	return index === 0 ? "never" : index === 1 ? "handled" : "always";
}

function dragMode(enabled: boolean): KeyboardDismissMode {
	return enabled ? "on-drag" : "none";
}

test "keyboard tap capture consumes never, preserves handled presses, and permits always" {
	const [taps, setTaps] = createSignal<int32>(0);
	const handles: ScrollViewHandle[] = [];
	let presses = 0;
	const dispose = render(element(<ScrollView keyboardShouldPersistTaps={tapMode(taps())} ref={(h: ScrollViewHandle): void => { handles.push(h); }}>
		<Pressable onPress={(): void => { presses += 1; }}><View /></Pressable>
	</ScrollView>), domHost(), documentBody());
	probe(handles[0].node).setAttribute("id", "neon-keyboard-probe");
	window.eval("const el = document.getElementById('neon-keyboard-probe'); const input = document.createElement('input'); input.id = 'neon-focused-input'; el.firstChild.appendChild(input); input.focus(); el.firstChild.firstChild.click();");
	assert presses === 0, "never consumes the first press to dismiss the keyboard";
	setTaps(1);
	window.eval("document.getElementById('neon-focused-input').focus(); document.getElementById('neon-keyboard-probe').firstChild.firstChild.click();");
	assert presses === 1, "handled permits a descendant Pressable to keep focus";
	setTaps(2);
	window.eval("document.getElementById('neon-focused-input').focus(); document.getElementById('neon-keyboard-probe').firstChild.firstChild.click();");
	assert presses === 2, "always permits all descendant presses";
	dispose();
}

test "interactive keyboard dismissal rejects explicitly on the browser" {
	let caught = "";
	try { render(element(<ScrollView keyboardDismissMode={"interactive"} />), domHost(), documentBody()); }
	catch (e) { caught = e.toString(); }
	assert caught.includes("interactive") && caught.includes("browser"), "names the unsupported native interaction: " + caught;
}

test "unmount removes drag listeners and disconnects content layout observation" {
	const handles: ScrollViewHandle[] = [];
	let calls = 0;
	const dispose = render(element(<ScrollView onContentSizeChange={(w: number, h: number): void => { calls += 1; }}
		onScrollBeginDrag={(e: NeonEvent): void => { calls += 1; }}
		ref={(h: ScrollViewHandle): void => { handles.push(h); }}>{rows()}</ScrollView>), domHost(), documentBody());
	await sleepAsync(100);
	const el = probe(handles[0].node);
	el.setAttribute("id", "neon-disposed-scroll");
	window.eval("window.neonDisposed = document.getElementById('neon-disposed-scroll');");
	dispose();
	const before = calls;
	window.eval("const el = window.neonDisposed; const touch = n => new Touch({identifier: 1, target: el, clientX: 0, clientY: n}); el.dispatchEvent(new TouchEvent('touchstart', {touches: [touch(0)]})); el.dispatchEvent(new TouchEvent('touchmove', {touches: [touch(100)]})); el.firstChild.style.height = '200px'; delete window.neonDisposed;");
	await sleepAsync(100);
	assert calls === before, "neither detached gestures nor a pending ResizeObserver invokes app code";
}

test "on-drag dismisses a focused input only after crossing the drag boundary" {
	const [mode, setMode] = createSignal(false);
	const handles: ScrollViewHandle[] = [];
	const dispose = render(element(<ScrollView keyboardDismissMode={dragMode(mode())} ref={(h: ScrollViewHandle): void => { handles.push(h); }}>
		<View style={{ height: 200 }} />
	</ScrollView>), domHost(), documentBody());
	const el = probe(handles[0].node);
	el.setAttribute("id", "neon-dismiss-probe");
	window.eval("const el = document.getElementById('neon-dismiss-probe'); const input = document.createElement('input'); input.id = 'neon-drag-input'; el.firstChild.appendChild(input); window.neonKeyboardDrag = y => { const touch = n => new Touch({identifier: 1, target: el, clientX: 0, clientY: n}); el.dispatchEvent(new TouchEvent('touchstart', {touches: [touch(0)]})); el.dispatchEvent(new TouchEvent('touchmove', {touches: [touch(y)]})); el.dispatchEvent(new TouchEvent('touchend', {touches: []})); el.setAttribute('data-focused', document.activeElement === input ? 'true' : 'false'); }; input.focus(); window.neonKeyboardDrag(20);");
	assert el.getAttribute("data-focused") === "true", "none preserves focus during a drag";
	setMode(true);
	window.eval("document.getElementById('neon-drag-input').focus(); window.neonKeyboardDrag(3);");
	assert el.getAttribute("data-focused") === "true", "a tap-sized movement does not dismiss";
	window.eval("window.neonKeyboardDrag(20); delete window.neonKeyboardDrag;");
	assert el.getAttribute("data-focused") === "false", "crossing the drag threshold blurs the input";
	dispose();
}

test "indicator visibility changes reactively without disabling imperative scrolling" {
	const [visible, setVisible] = createSignal(true);
	const handles: ScrollViewHandle[] = [];
	const dispose = render(element(<ScrollView showsHorizontalScrollIndicator={visible()} showsVerticalScrollIndicator={visible()}
		scrollEnabled={false} style={{ height: 100 }} ref={(h: ScrollViewHandle): void => { handles.push(h); }}>{rows()}</ScrollView>), domHost(), documentBody());
	const el = probe(handles[0].node);
	el.setAttribute("id", "neon-indicator-probe");
	setVisible(false);
	window.eval("const el = document.getElementById('neon-indicator-probe'); el.setAttribute('data-scrollbar', getComputedStyle(el).scrollbarWidth);");
	assert el.getAttribute("data-scrollbar") === "none", "both disabled indicators remove the actual browser scrollbar";
	handles[0].scrollTo({ y: 1000, animated: false });
	assert el.scrollTop === 300, "scrollEnabled false does not block an imperative tail jump";
	setVisible(true);
	window.eval("const el = document.getElementById('neon-indicator-probe'); el.setAttribute('data-scrollbar', getComputedStyle(el).scrollbarWidth);");
	assert el.getAttribute("data-scrollbar") === "auto", "re-enabling restores browser indicators";
	dispose();
}

test "a refresh declined by the controlled prop stops immediately and rearms" {
	const handles: ScrollViewHandle[] = [];
	let calls = 0;
	const dispose = render(element(<ScrollView refreshing={false} onRefresh={(): void => { calls += 1; }}
		style={{ height: 100 }} ref={(h: ScrollViewHandle): void => { handles.push(h); }}>{rows()}</ScrollView>), domHost(), documentBody());
	const el = probe(handles[0].node);
	el.setAttribute("id", "neon-declined-refresh");
	window.eval("const el = document.getElementById('neon-declined-refresh'); const touch = y => new Touch({identifier: 1, target: el, clientX: 0, clientY: y}); const pull = () => { el.dispatchEvent(new TouchEvent('touchstart', {touches: [touch(0)]})); el.dispatchEvent(new TouchEvent('touchmove', {touches: [touch(100)], cancelable: true})); el.dispatchEvent(new TouchEvent('touchend', {touches: []})); }; pull(); pull(); el.setAttribute('data-busy', el.querySelector('.neon-refresh-indicator').getAttribute('aria-busy'));");
	assert calls === 2, "a false controlled value permits another refresh gesture";
	assert el.getAttribute("data-busy") === "false", "the native gesture does not override the controlled value";
	dispose();
}
