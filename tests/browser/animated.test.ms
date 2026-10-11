import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View, Pressable } from "../../src/components/primitives";
import { createSignal } from "../../src/core/signal";
import { sleepAsync } from "std/core/promise";
import { Animated } from "../../src/animation/animated";
import { AnimatedValue, AnimatedNode } from "../../src/animation/nodes";
import { Easing } from "../../src/animation/easing";
import { LayoutAnimation } from "../../src/animation/layoutAnimation";
import { setFrameDriver } from "../../src/animation/frame";
import { EndResult } from "../../src/animation/animation";

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

function probe(n: HostNode): HTMLElement {
	return n as unknown as HTMLElement;
}

test "Animated.View opacity and translate change across real animation frames" {
	setFrameDriver(null);
	const v = new AnimatedValue(0);
	const nodes: HostNode[] = [];
	render(element(<Animated.View ref={(n: HostNode): void => { nodes.push(n); }} style={{
		width: 40, height: 40, backgroundColor: "#333",
		opacity: v.get(),
		transform: `translateX(${v.get() * 100}px) rotate(${v.get() * 90}deg)`,
	}} />), domHost(), documentBody());
	const el = probe(nodes[0]);
	assert el.style.opacity === "0", "starts at 0: " + el.style.opacity;
	let finished = false;
	Animated.timing(v, { toValue: 1, duration: 400, easing: Easing.linear }).start((r: EndResult): void => { finished = r.finished; });
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
	render(element(<View ref={(n: HostNode): void => { nodes.push(n); }} style={{ width: 100, height: open() ? 200 : 20, backgroundColor: "#0a0" }} />), domHost(), documentBody());
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
