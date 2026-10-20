import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { Host, HostNode, MockNode, mockNode, mockHost, render, mockToString, mockAreaHub } from "../../src/render/host";
import { VoidAreaHandle, AreaKeyAction, AreaPointerKind, AreaKeyEvent, AreaKeyMod, AreaPointerEvent, AreaPreedit, AreaResize, AreaLayer, AreaRgba, Unsubscribe, createAreaHub } from "../../src/render/voidAreaHandle";
import { onCleanup } from "../../src/core/cleanup";
import { createContext, useContext } from "../../src/render/context";
import { Void, View, ViewHandle, Text } from "../../src/components/primitives";
import { flush } from "../../src/core/runtime";

test "Void mounts its children into the area the host opens" {
	const root: MockNode = mockNode("root");
	render(element(<Void><View><Text>hi</Text></View></Void>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><void><voidroot><view><text>hi</text></view></voidroot></void></root>", mockToString(root);
}

test "Void takes the same style as View" {
	const root: MockNode = mockNode("root");
	render(element(<Void style={{ flexGrow: 1, backgroundColor: "#102030" }}><View /></Void>), mockHost(), root as unknown as HostNode);
	const v = root.children[0];
	assert v.tag === "void", "outer element is the void tag";
	assert v.style !== null, "style reached the void element";
	assert v.style!.flexGrow === 1, "flexGrow";
	assert v.style!.backgroundColor === "#102030", "backgroundColor";
}

test "disposing the owner releases the area" {
	const root: MockNode = mockNode("root");
	const dispose = render(element(<Void><View /></Void>), mockHost(), root as unknown as HostNode);
	const v = root.children[0];
	assert mockToString(v).indexOf("released") < 0, "not released while mounted";
	dispose();
	assert mockToString(v).indexOf("released=\"true\"") >= 0, "released on dispose: " + mockToString(v);
}

interface Theme { accent: string; }

test "context and signals cross into the area" {
	const T = createContext<Theme>({ accent: "red" });
	const [n, setN] = createSignal(1);
	const root: MockNode = mockNode("root");
	render(element(
		<T value={{ accent: "blue" }}>
			<Void><Text>{useContext(T).accent}{n().toString()}</Text></Void>
		</T>
	), mockHost(), root as unknown as HostNode);
	assert mockToString(root).indexOf("<text>blue1</text>") >= 0, "context read inside: " + mockToString(root);
	setN(2);
	flush();
	assert mockToString(root).indexOf("<text>blue2</text>") >= 0, "signal tracked inside: " + mockToString(root);
}

function keyEvent(text: string): AreaKeyEvent {
	return { action: AreaKeyAction.Press, key: 65, scancode: 30, mods: 0 as BitSet<AreaKeyMod>, consumedMods: 0 as BitSet<AreaKeyMod>, unshifted: 97, text };
}

test "the ref of a Void receives the area handle, not the outer node, after the children mount" {
	let handle: VoidAreaHandle | null = null;
	const order: string[] = [];
	const root: MockNode = mockNode("root");
	const grab = (h: VoidAreaHandle): void => {
		handle = h;
		order.push("void");
	};
	const grabView: (h: ViewHandle) => void = (h) => { order.push("view"); };
	render(element(<Void ref={grab}><View ref={grabView} /></Void>), mockHost(), root as unknown as HostNode);
	assert handle !== null, "ref ran with a handle";
	assert order.join(",") === "view,void", "the Void ref ran after its children mounted: " + order.join(",");
}

test "the handle reports size and scale and forwards raw input to its subscribers" {
	const root: MockNode = mockNode("root");
	let handle: VoidAreaHandle | null = null;
	const log: string[] = [];
	const grab = (h: VoidAreaHandle): void => {
		handle = h;
		h.onKey((e: AreaKeyEvent): void => { log.push("key:" + e.text + ":" + e.scancode.toString() + ":" + e.unshifted.toString()); });
		h.onText((t: string): void => { log.push("text:" + t); });
		h.onPreedit((e: AreaPreedit): void => { log.push("preedit:" + e.text + ":" + e.cursor.toString()); });
		h.onPointer((e: AreaPointerEvent): void => { log.push("pointer:" + e.pixelX.toString() + ":" + (e.kind === AreaPointerKind.Wheel ? "wheel" : "other")); });
		h.onFocus((f: boolean): void => { log.push("focus:" + f.toString()); });
		h.onResize((e: AreaResize): void => { log.push("resize:" + e.pixelWidth.toString() + "x" + e.pixelHeight.toString()); });
	};
	render(element(<Void ref={grab}><View /></Void>), mockHost(), root as unknown as HostNode);
	const hub = mockAreaHub(root.children[0]);
	hub.resize({ pixelWidth: 800, pixelHeight: 600, scale: 1.5 });
	hub.key(keyEvent("a"));
	hub.text("b");
	hub.preedit({ text: "c", cursor: 1 });
	hub.pointer({ kind: AreaPointerKind.Wheel, pixelX: 3.0, pixelY: 4.0, button: 0, pressed: false, dx: 0.0, dy: -1.0 });
	hub.focus(true);
	const h = handle as VoidAreaHandle;
	assert h.pixelWidth() === 800 && h.pixelHeight() === 600, "size " + h.pixelWidth().toString();
	assert h.scale() === 1.5, "scale";
	assert log.join(",") === "resize:800x600,key:a:30:97,text:b,preedit:c:1,pointer:3:wheel,focus:true", log.join(",");
	h.requestFrame();
	h.setImeRect(1, 2, 3, 4);
	assert mockToString(root).indexOf("frameRequested=\"true\"") >= 0, "requestFrame reached the host";
	assert mockToString(root).indexOf("imeRect=\"1,2,3,4\"") >= 0, "setImeRect reached the host";
}

test "a subscription ends on unsubscribe and when the owner disposes" {
	const root: MockNode = mockNode("root");
	const log: string[] = [];
	let off: (() => void) | null = null;
	const grab = (h: VoidAreaHandle): void => {
		h.onText((t: string): void => { log.push("kept:" + t); });
		off = h.onText((t: string): void => { log.push("dropped:" + t); });
	};
	const dispose = render(element(<Void ref={grab}><View /></Void>), mockHost(), root as unknown as HostNode);
	const hub = mockAreaHub(root.children[0]);
	(off as () => void)();
	hub.text("1");
	dispose();
	hub.text("2");
	assert log.join(",") === "kept:1", log.join(",");
}

function drawing(log: string[]): (h: VoidAreaHandle) => void {
	onCleanup((): void => { log.push("setup cleanup"); });
	return (h: VoidAreaHandle): void => { log.push("apply"); };
}

test "a directive factory and a plain callback both receive the handle" {
	const root: MockNode = mockNode("root");
	const log: string[] = [];
	const plain = (h: VoidAreaHandle): void => { log.push("plain"); };
	const dispose = render((h: Host, p: HostNode, b: HostNode | null): void => {
		element(<Void ref={[drawing(log), plain]}><View /></Void>)(h, p, b);
	}, mockHost(), root as unknown as HostNode);
	assert log.join(",") === "apply,plain", log.join(",");
	dispose();
	assert log.join(",") === "apply,plain,setup cleanup", log.join(",");
}

test "a layer removed by an earlier layer during the frame is neither prepared nor drawn" {
	const hub = createAreaHub({ initialPixelWidth: 10, initialPixelHeight: 10, requestFrame: (): void => {}, setImeRect: (x: int32, y: int32, w: int32, h: int32): void => {} });
	const log: string[] = [];
	let removeSecond: Unsubscribe | null = null;
	let removeThird: Unsubscribe | null = null;
	const layer = (name: string, onPrepare: () => void, onDraw: () => void): AreaLayer => ({
		shown: (): boolean => true,
		prepare: (pixelWidth: int32, pixelHeight: int32, background: AreaRgba): void => { log.push("prepare " + name); onPrepare(); },
		draw: (): void => { log.push("draw " + name); onDraw(); },
	});
	hub.addLayer(layer("a", (): void => { (removeSecond as Unsubscribe)(); }, (): void => { (removeThird as Unsubscribe)(); }));
	removeSecond = hub.addLayer(layer("b", (): void => {}, (): void => {}));
	removeThird = hub.addLayer(layer("c", (): void => {}, (): void => {}));
	hub.prepareLayers(10, 10, { r: 0.0, g: 0.0, b: 0.0, a: 1.0 });
	hub.drawLayers();
	assert log.join(",") === "prepare a,prepare c,draw a", log.join(",");
	assert hub.layers().length === 1, "only a stays registered";
}

test "a layer hidden at prepare is skipped, and one hidden after its prepare still draws that frame" {
	const hub = createAreaHub({ initialPixelWidth: 10, initialPixelHeight: 10, requestFrame: (): void => {}, setImeRect: (x: int32, y: int32, w: int32, h: int32): void => {} });
	const log: string[] = [];
	const visible = [true, false, true];
	let hideFirstInThird = false;
	const names = ["a", "b", "c"];
	for (let i = 0; i < 3; i += 1) {
		const at = i;
		hub.addLayer({
			shown: (): boolean => visible[at],
			prepare: (pixelWidth: int32, pixelHeight: int32, background: AreaRgba): void => {
				log.push("prepare " + names[at]);
				if (at === 2 && hideFirstInThird) { visible[0] = false; }
			},
			draw: (): void => { log.push("draw " + names[at]); },
		});
	}
	const frame = (): string => {
		log.length = 0;
		hub.prepareLayers(10, 10, { r: 0.0, g: 0.0, b: 0.0, a: 1.0 });
		hub.drawLayers();
		return log.join(",");
	};
	const hiddenB = frame();
	assert hiddenB === "prepare a,prepare c,draw a,draw c", "a hidden layer is neither prepared nor drawn: " + hiddenB;
	visible[1] = true;
	hideFirstInThird = true;
	const heldA = frame();
	assert heldA === "prepare a,prepare b,prepare c,draw a,draw b,draw c", "a layer hidden after its prepare draws what it prepared: " + heldA;
	hideFirstInThird = false;
	const goneA = frame();
	assert goneA === "prepare b,prepare c,draw b,draw c", "the next frame skips it: " + goneA;
	visible[0] = true;
	const back = frame();
	assert back === "prepare a,prepare b,prepare c,draw a,draw b,draw c", "shown again, it keeps its place: " + back;
	assert hub.layers().length === 3, "hiding never unregisters";
}

test "a subscriber removed by an earlier one during an emit is not called" {
	const hub = createAreaHub({ initialPixelWidth: 10, initialPixelHeight: 10, requestFrame: (): void => {}, setImeRect: (x: int32, y: int32, w: int32, h: int32): void => {} });
	const log: string[] = [];
	let off: Unsubscribe | null = null;
	hub.handle.onText((t: string): void => { log.push("first " + t); (off as Unsubscribe)(); });
	off = hub.handle.onText((t: string): void => { log.push("second " + t); });
	hub.text("x");
	hub.text("y");
	assert log.join(",") === "first x,first y", log.join(",");
}
