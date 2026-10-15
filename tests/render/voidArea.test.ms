import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { Host, HostNode, MockNode, mockNode, mockHost, render, mockToString, mockAreaHub } from "../../src/render/host";
import { VoidAreaHandle, AreaKeyAction, AreaPointerKind, AreaKeyEvent, AreaKeyMod, AreaPointerEvent, AreaPreedit, AreaResize } from "../../src/render/voidAreaHandle";
import { onCleanup } from "../../src/core/cleanup";
import { createContext, useContext } from "../../src/render/context";
import { Void, View, ViewHandle, Text } from "../../src/components/primitives";

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
		<T.Provider value={{ accent: "blue" }}>
			<Void><Text>{useContext(T).accent}{n().toString()}</Text></Void>
		</T.Provider>
	), mockHost(), root as unknown as HostNode);
	assert mockToString(root).indexOf("<text>blue1</text>") >= 0, "context read inside: " + mockToString(root);
	setN(2);
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
