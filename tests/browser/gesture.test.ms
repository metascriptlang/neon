import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View, Pressable, Text } from "../../src/components/primitives";
import { PanResponder, PanResponderGestureState } from "../../src/components/panResponder";

extern class HTMLElement {
	extern getAttribute(name: cstring): string;
	extern setAttribute(name: cstring, value: cstring): void;
	extern remove(): void;
}

extern class window {
	static extern eval(code: cstring): void;
}

extern class document {
	static extern getElementById(id: cstring): HTMLElement;
}

const DRAG = "window.neonDrag = (id, points) => { const el = document.getElementById(id); const tick = () => { const s = performance.now(); while (performance.now() - s < 2) {} }; const at = (type, x) => { tick(); return new PointerEvent(type, { bubbles: true, cancelable: true, pointerId: 7, pointerType: 'touch', clientX: x, clientY: 10 }); }; el.dispatchEvent(at('pointerdown', points[0])); for (let i = 1; i < points.length; i++) el.dispatchEvent(at('pointermove', points[i])); el.dispatchEvent(at('pointerup', points[points.length - 1])); };";

test "a DOM pan row claims a horizontal drag that starts on a Pressable inside it, and the press does not fire" {
	window.eval(DRAG);
	let log = "";
	const pan = PanResponder.create({
		onMoveShouldSetPanResponder: (e: NeonEvent, g: PanResponderGestureState): boolean => Math.abs(g.dx) > 10,
		onPanResponderGrant: (e: NeonEvent, g: PanResponderGestureState): void => { log += "grant;"; },
		onPanResponderMove: (e: NeonEvent, g: PanResponderGestureState): void => { log += `move ${g.dx};`; },
		onPanResponderRelease: (e: NeonEvent, g: PanResponderGestureState): void => { log += `release ${g.dx};`; },
	});
	render(element(<View {...pan.panHandlers} accessibilityLabel="neon-pan-row">
		<Pressable onPressIn={(e: NeonEvent): void => { log += "in;"; }} onPress={(e: NeonEvent): void => { log += "press;"; }}><Text>open</Text></Pressable>
	</View>), domHost(), documentBody());
	window.eval("document.querySelector('[aria-label=\"neon-pan-row\"]').firstChild.id = 'neon-pan-button'");
	window.eval("window.neonDrag('neon-pan-button', [100, 104, 130, 150])");
	assert log === "in;grant;move 20;release 20;", "the drag pans and does not press: " + log;
}

test "a DOM tap inside a pan row still presses" {
	window.eval(DRAG);
	let log = "";
	const pan = PanResponder.create({
		onMoveShouldSetPanResponder: (e: NeonEvent, g: PanResponderGestureState): boolean => Math.abs(g.dx) > 10,
	});
	render(element(<View {...pan.panHandlers} accessibilityLabel="neon-tap-row">
		<Pressable onPress={(e: NeonEvent): void => { log += "press;"; }}><Text>open</Text></Pressable>
	</View>), domHost(), documentBody());
	window.eval("const b = document.querySelector('[aria-label=\"neon-tap-row\"]').firstChild; b.id = 'neon-tap-button'; window.neonDrag('neon-tap-button', [100, 102]); b.click();");
	assert log === "press;", "a tap presses: " + log;
}
