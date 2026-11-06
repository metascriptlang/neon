import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View, ViewHandle } from "../../src/components/primitives";
import { createSignal } from "../../src/core/signal";
import { sleepAsync } from "std/core/promise";
import { LayoutAnimation } from "../../src/motion/layoutAnimation";

extern class CSSStyleDeclaration {
	transition: string;
}

extern class HTMLElement {
	style: CSSStyleDeclaration;
	offsetHeight: number;
	extern remove(): void;
}

extern function preferReducedMotion(): () => void from
	"(() => { const real = globalThis.matchMedia; globalThis.matchMedia = (q) => q === '(prefers-reduced-motion: reduce)' ? { matches: true, media: q } : real.call(globalThis, q); return () => { globalThis.matchMedia = real; }; })()";

function probe(n: HostNode): HTMLElement {
	return n as unknown as HTMLElement;
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
