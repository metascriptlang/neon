import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View, ViewHandle } from "../../src/components/primitives";
import { sleepAsync } from "std/core/promise";
import { ElementValue, elementValue, motionElements } from "../../src/motion/waapi";
import { MotionPolicy } from "pulse/src/policy";
import { spring, timing } from "pulse/src/value";
import { Easing } from "pulse/src/easing";

extern class Animation {}

extern class CSSStyleDeclaration {
	translate: string;
	opacity: string;
}

extern class HTMLElement {
	style: CSSStyleDeclaration;
	extern getAnimations(): Animation[];
	extern remove(): void;
}

extern function firstEasing(el: HTMLElement): string from
	"(el => { const a = el.getAnimations(); return a.length === 0 ? '' : a[0].effect.getKeyframes()[0].easing; })(#)";

// Chrome before 113, Firefox before 112 and Safari before 17.2 throw this TypeError for linear().
extern function refuseLinearEasing(): void from
	"(() => { const animate = Element.prototype.animate; const linear = (e) => typeof e === 'string' && e.includes('linear('); Element.prototype.animate = function (keyframes, options) { if (linear(options?.easing) || (Array.isArray(keyframes) && keyframes.some((k) => linear(k.easing)))) { throw new TypeError(\"Failed to execute 'animate' on 'Element': invalid easing\"); } return animate.call(this, keyframes, options); }; })()";

function mount(): HostNode {
	const nodes: HostNode[] = [];
	render(
		element(
			<View
				ref={(h: ViewHandle): void => { nodes.push(h.node); }}
				style={{ width: 40, height: 40 }}
			/>,
		),
		domHost(),
		documentBody(),
	);
	return nodes[0];
}

function boxValue(node: HostNode, property: string): ElementValue {
	const elements = motionElements([{ slot: "box", node }]);
	return elementValue(0, new MotionPolicy(), elements, "box", property) as ElementValue;
}

test "without CSS linear() a spring and an eased timing run on the evaluator, and a linear timing still hands over" {
	refuseLinearEasing();
	const node = mount();
	const el = node as unknown as HTMLElement;
	const sprung = boxValue(node, "translateX");
	sprung.animate(spring(100));
	const eased = boxValue(node, "opacity");
	eased.animate(timing(1, { duration: 300 }));
	assert !sprung.handedOver && !eased.handedOver && el.getAnimations().length === 0,
		"nothing handed over: " + el.getAnimations().length.toString();
	await sleepAsync(100);
	assert el.style.translate !== "" && el.style.opacity !== "", "the evaluator writes inline: " +
		el.style.translate + " " + el.style.opacity;
	sprung.dispose();
	eased.dispose();
	const linear = boxValue(node, "translateX");
	linear.animate(timing(50, { duration: 300, easing: Easing.linear }));
	assert linear.handedOver && firstEasing(el) === "linear", firstEasing(el);
	linear.dispose();
	el.remove();
}
