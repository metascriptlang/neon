import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View, ViewHandle } from "../../src/components/primitives";
import { createSignal } from "../../src/core/signal";
import { sleepAsync } from "std/core/promise";
import { LayoutAnimation, LayoutAnimationPresets, LayoutAnimationType } from "../../src/motion/layoutAnimation";

extern class CSSStyleDeclaration {
	transition: string;
}

extern class HTMLElement {
	style: CSSStyleDeclaration;
	offsetHeight: number;
	extern remove(): void;
}

extern function refuseLinearEasing(): void from
	"(() => { const animate = Element.prototype.animate; Element.prototype.animate = function (keyframes, options) { if (typeof options?.easing === 'string' && options.easing.includes('linear(')) { throw new TypeError(\"Failed to execute 'animate' on 'Element': invalid easing\"); } return animate.call(this, keyframes, options); }; })()";

function grows(type: LayoutAnimationType | null): HTMLElement {
	const [open, setOpen] = createSignal(false);
	const nodes: HostNode[] = [];
	render(element(<View ref={(h: ViewHandle): void => { nodes.push(h.node); }} style={{ width: 100, height: open() ? 200 : 20 }} />), domHost(), documentBody());
	if (type === null) {
		LayoutAnimation.configureNext(LayoutAnimationPresets.spring);
	} else {
		LayoutAnimation.configureNext(LayoutAnimation.create(400, type as LayoutAnimationType, "opacity"));
	}
	setOpen(true);
	return nodes[0] as unknown as HTMLElement;
}

test "without CSS linear() an eased and a spring LayoutAnimation transition on a timing function the browser keeps" {
	refuseLinearEasing();
	await sleepAsync(500);
	const eased = grows("easeInEaseOut");
	const sprung = grows(null);
	await sleepAsync(200);
	assert eased.style.transition.indexOf("linear(") < 0 && sprung.style.transition.indexOf("linear(") < 0,
		"no linear(): " + eased.style.transition + " | " + sprung.style.transition;
	assert eased.offsetHeight > 20 && eased.offsetHeight < 200, "eased mid-transition: " + eased.offsetHeight.toString() + " " + eased.style.transition;
	assert sprung.offsetHeight > 20 && sprung.offsetHeight < 200, "spring mid-transition: " + sprung.offsetHeight.toString();
	await sleepAsync(800);
	assert eased.offsetHeight === 200 && sprung.offsetHeight === 200, "both land";
	eased.remove();
	sprung.remove();
}
