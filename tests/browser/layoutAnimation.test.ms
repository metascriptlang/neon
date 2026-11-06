import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View, ViewHandle } from "../../src/components/primitives";
import { createSignal } from "../../src/core/signal";
import { sleepAsync } from "std/core/promise";
import { LayoutAnimation } from "../../src/motion/layoutAnimation";
import { Show } from "../../src/macros/ui/flow";

extern class CSSStyleDeclaration {
	height: string;
	opacity: string;
	transition: string;
	overflow: string;
}

extern class HTMLElement {
	style: CSSStyleDeclaration;
	offsetHeight: number;
	extern remove(): void;
}

extern function countForcedLayouts(): void from
	"(() => { let s = globalThis.__neonLayoutReads; if (!s) { s = { forced: 0, on: false, observer: new MutationObserver(() => {}) }; globalThis.__neonLayoutReads = s; s.observer.observe(document.body, { attributes: true, childList: true, subtree: true }); for (const name of ['offsetWidth', 'offsetHeight']) { const d = Object.getOwnPropertyDescriptor(HTMLElement.prototype, name); Object.defineProperty(HTMLElement.prototype, name, { ...d, get() { if (s.on && s.observer.takeRecords().length > 0) { s.forced += 1; } return d.get.call(this); } }); } } s.observer.takeRecords(); s.forced = 0; s.on = true; })()";
extern function forcedLayouts(): number from
	"(() => { const s = globalThis.__neonLayoutReads; s.on = false; return s.forced; })()";
extern function preferReducedMotion(): () => void from
	"(() => { const real = globalThis.matchMedia; globalThis.matchMedia = (q) => q === '(prefers-reduced-motion: reduce)' ? { matches: true, media: q } : real.call(globalThis, q); return () => { globalThis.matchMedia = real; }; })()";

function probe(n: HostNode): HTMLElement {
	return n as unknown as HTMLElement;
}

test "a view that appears and then resizes under a second configureNext keeps no transition afterwards" {
	const [shown, setShown] = createSignal(false);
	const [height, setHeight] = createSignal(100);
	const outer: HostNode[] = [];
	const nodes: HostNode[] = [];
	render(element(<View ref={(h: ViewHandle): void => { outer.push(h.node); }} style={{ width: 100 }}>
		<Show when={shown()}>
			<View ref={(h: ViewHandle): void => { nodes.push(h.node); }} style={{ width: 100, height: height(), backgroundColor: "#a0a" }} />
		</Show>
	</View>), domHost(), documentBody());
	LayoutAnimation.configureNext(LayoutAnimation.create(200, "linear", "opacity"));
	setShown(true);
	await sleepAsync(100);
	LayoutAnimation.configureNext(LayoutAnimation.create(200, "linear", "opacity"));
	setHeight(150);
	await sleepAsync(120);
	const el = probe(nodes[0]);
	assert el.offsetHeight > 100 && el.offsetHeight < 150, "the second animation resizes: " + el.offsetHeight.toString();
	await sleepAsync(400);
	assert el.style.transition === "" && el.style.overflow === "" && el.style.opacity === "",
		"the original inline style is back: " + el.style.transition + "|" + el.style.overflow + "|" + el.style.opacity;
	assert el.offsetHeight === 150, "lands: " + el.offsetHeight.toString();
	probe(outer[0]).remove();
}

test "a configureNext over a running resize ends at the content's size, not a height the first one fixed" {
	const [inner, setInner] = createSignal(20);
	const outer: HostNode[] = [];
	render(element(<View ref={(h: ViewHandle): void => { outer.push(h.node); }} style={{ width: 100 }}>
		<View style={{ width: 100, height: inner(), backgroundColor: "#0a0" }} />
	</View>), domHost(), documentBody());
	const el = probe(outer[0]);
	LayoutAnimation.configureNext(LayoutAnimation.create(200, "linear", "opacity"));
	setInner(100);
	await sleepAsync(100);
	LayoutAnimation.configureNext(LayoutAnimation.create(200, "linear", "opacity"));
	setInner(160);
	await sleepAsync(120);
	assert el.offsetHeight > 20 && el.offsetHeight < 160, "the second animation runs: " + el.offsetHeight.toString();
	await sleepAsync(400);
	assert el.style.height === "" && el.style.transition === "" && el.style.overflow === "",
		"the original inline style is back: " + el.style.height + "|" + el.style.transition + "|" + el.style.overflow;
	assert el.offsetHeight === 160, "follows its content: " + el.offsetHeight.toString();
	el.remove();
}

test "the frame that starts a LayoutAnimation forces layout a fixed number of times, whatever the count of views" {
	const [open, setOpen] = createSignal(false);
	const outer: HostNode[] = [];
	render(element(<View ref={(h: ViewHandle): void => { outer.push(h.node); }} style={{ width: 100 }}>
		<View style={{ height: open() ? 30 : 10 }} />
		<View style={{ height: open() ? 30 : 10 }} />
		<View style={{ height: open() ? 30 : 10 }} />
		<View style={{ height: open() ? 30 : 10 }} />
		<View style={{ height: open() ? 30 : 10 }} />
		<View style={{ height: open() ? 30 : 10 }} />
		<View style={{ height: open() ? 30 : 10 }} />
		<View style={{ height: open() ? 30 : 10 }} />
	</View>), domHost(), documentBody());
	const el = probe(outer[0]);
	countForcedLayouts();
	LayoutAnimation.configureNext(LayoutAnimation.create(100, "linear", "opacity"));
	setOpen(true);
	await sleepAsync(50);
	const forced = forcedLayouts();
	assert forced <= 2, "forced layouts for nine resized views: " + forced.toString();
	await sleepAsync(200);
	assert el.offsetHeight === 240, "lands: " + el.offsetHeight.toString();
	el.remove();
}

test "a browser user's reduced motion preference lands a LayoutAnimation at once" {
	const restore = preferReducedMotion();
	const [open, setOpen] = createSignal(false);
	const nodes: HostNode[] = [];
	render(element(<View ref={(h: ViewHandle): void => { nodes.push(h.node); }} style={{ width: 100, height: open() ? 200 : 20 }} />), domHost(), documentBody());
	const el = probe(nodes[0]);
	LayoutAnimation.configureNext(LayoutAnimation.create(400, "linear", "opacity"));
	setOpen(true);
	await sleepAsync(50);
	restore();
	assert el.offsetHeight === 200 && el.style.transition === "", "no transition: " + el.offsetHeight.toString() + " " + el.style.transition;
	el.remove();
}
