import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View, ViewHandle, Pressable } from "../../src/components/primitives";
import { createSignal } from "../../src/core/signal";
import { sleepAsync } from "std/core/promise";
import { Easing } from "pulse/src/easing";
import { timing } from "pulse/src/value";
import { createAnimatedValue } from "../../src/motion/neonValues";
import { LayoutAnimation } from "../../src/motion/layoutAnimation";
import { setFrameDriver } from "../../src/animation/frame";
import { Show } from "../../src/macros/ui/flow";

extern class CSSStyleDeclaration {
	opacity: string;
	transform: string;
}

extern class HTMLElement {
	style: CSSStyleDeclaration;
	offsetHeight: number;
	extern remove(): void;
	extern setAttribute(name: cstring, value: cstring): void;
}

extern function shownWidth(el: HTMLElement): number from "(e => e.getBoundingClientRect().width)(#)";
extern function shownHeight(el: HTMLElement): number from "(e => e.getBoundingClientRect().height)(#)";
extern function shownOpacity(el: HTMLElement): string from "(e => getComputedStyle(e).opacity)(#)";

function probe(n: HostNode): HTMLElement {
	return n as unknown as HTMLElement;
}

test "an animated value's opacity and translate change across real animation frames" {
	setFrameDriver(null);
	const [shown, v] = createAnimatedValue(0);
	const nodes: HostNode[] = [];
	render(element(<View ref={(h: ViewHandle): void => { nodes.push(h.node); }} style={{
		width: 40, height: 40, backgroundColor: "#333",
		opacity: shown(),
		transform: `translateX(${shown() * 100}px) rotate(${shown() * 90}deg)`,
	}} />), domHost(), documentBody());
	const el = probe(nodes[0]);
	assert el.style.opacity === "0", "starts at 0: " + el.style.opacity;
	let finished = false;
	v.animate(
		timing(1, { duration: 400, easing: Easing.linear }),
		(done: boolean): void => { finished = done; },
	);
	await sleepAsync(200);
	const mid = parseFloat(el.style.opacity);
	assert mid > 0.1 && mid < 0.9, "mid-animation opacity " + el.style.opacity;
	assert el.style.transform.indexOf("translateX(") >= 0 && el.style.transform !== "translateX(0px) rotate(0deg)", "moving: " + el.style.transform;
	await sleepAsync(400);
	assert finished && el.style.opacity === "1", "settled: " + el.style.opacity;
	assert el.style.transform === "translateX(100px) rotate(90deg)", el.style.transform;
	el.remove();
}

test "LayoutAnimation.configureNext transitions a height change in the browser" {
	const [open, setOpen] = createSignal(false);
	const nodes: HostNode[] = [];
	render(element(<View ref={(h: ViewHandle): void => { nodes.push(h.node); }} style={{ width: 100, height: open() ? 200 : 20, backgroundColor: "#0a0" }} />), domHost(), documentBody());
	const el = probe(nodes[0]);
	assert el.offsetHeight === 20;
	LayoutAnimation.configureNext(LayoutAnimation.create(400, "linear", "opacity"));
	setOpen(true);
	await sleepAsync(200);
	assert el.offsetHeight > 20 && el.offsetHeight < 200, "mid-transition height " + el.offsetHeight.toString();
	await sleepAsync(500);
	assert el.offsetHeight === 200, "lands at 200: " + el.offsetHeight.toString();
	el.remove();
}

test "a height written while LayoutAnimation runs survives the animation's restore" {
	const [height, setHeight] = createSignal(20);
	const nodes: HostNode[] = [];
	render(element(<View ref={(h: ViewHandle): void => { nodes.push(h.node); }} style={{ width: 100, height: height(), backgroundColor: "#00a" }} />), domHost(), documentBody());
	const el = probe(nodes[0]);
	LayoutAnimation.configureNext(LayoutAnimation.create(200, "linear", "opacity"));
	setHeight(200);
	await sleepAsync(100);
	setHeight(60);
	await sleepAsync(400);
	assert el.offsetHeight === 60, "the later write stands: " + el.offsetHeight.toString();
	el.remove();
}

test "a view created under a scaleY create grows its height and keeps its opacity" {
	const [shown, setShown] = createSignal(false);
	const nodes: HostNode[] = [];
	const outer: HostNode[] = [];
	render(element(<View ref={(h: ViewHandle): void => { outer.push(h.node); }} style={{ width: 100 }}>
		<Show when={shown()}>
			<View ref={(h: ViewHandle): void => { nodes.push(h.node); }} style={{ width: 100, height: 100, backgroundColor: "#a0a" }} />
		</Show>
	</View>), domHost(), documentBody());
	LayoutAnimation.configureNext(LayoutAnimation.create(400, "linear", "scaleY"));
	setShown(true);
	await sleepAsync(200);
	const el = probe(nodes[0]);
	const midHeight = shownHeight(el);
	assert shownWidth(el) === 100 && midHeight > 10 && midHeight < 90, "grows tall only: " + shownWidth(el).toString() + "x" + midHeight.toString();
	assert shownOpacity(el) === "1", "scale leaves opacity alone: " + shownOpacity(el);
	await sleepAsync(400);
	assert shownHeight(el) === 100, "lands: " + shownHeight(el).toString();
	probe(outer[0]).remove();
}
