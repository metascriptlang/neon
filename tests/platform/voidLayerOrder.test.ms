import { Accessor, createSignal } from "../../src/core/signal";
import { createRenderEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Errored, Show } from "../../src/macros/ui/flow";
import { render } from "../../src/render/host";
import { Host, HostNode, NeonNode, VoidArea } from "../../src/render/hostTypes";
import { AreaLayer, Unsubscribe } from "../../src/render/voidAreaHandle";
import { layerAnchor } from "../../src/render/voidLayer";
import { useContext } from "../../src/render/context";
import { getVoidAreaContext } from "../../src/render/voidScope";
import { onCleanup } from "../../src/core/cleanup";
import { Void, View, Text } from "../../src/components/primitives";
import { Scene2D } from "../../src/components/scene2d";
import { Scene3D } from "../../src/components/scene3d";
import { VoidNode } from "../../src/platform/void/host";
import { AreaWindow, WindowArea, windowHost, windowNode, layersInPaintOrder } from "../../src/platform/void/windowHost";
import { FontId, addFont } from "../../../void/src/void2d/font";
import { NodeRef, clearChanges, parent, getChildIndex, numChildren } from "../../../void/src/void2d/node";
import { paint as paintScene } from "../../../void/src/void2d/scene";
import { frameEnd } from "../../../void/src/void2d/draw";

const FONT_PATH = "../void/assets/font.ttf";

function loadedFont(): FontId {
	const r = addFont(FONT_PATH);
	if (!r.ok) { throw new Error("the test font did not load from " + FONT_PATH + "; run from the Neon checkout root beside ../void"); }
	return r.value;
}

function testWindow(log: string[], areas: WindowArea[]): AreaWindow {
	return {
		name: "test window",
		font: loadedFont(),
		pixelWidth: (): int32 => 640 as int32,
		pixelHeight: (): int32 => 360 as int32,
		requestFrame: (): void => { log.push("frame"); },
		dirty: (): void => { log.push("dirty"); },
		setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => {},
		opened: (area: WindowArea): void => { areas.push(area); },
		released: (area: WindowArea): void => {},
	};
}

function drawn(area: WindowArea): void {
	area.vh.scene.paintScene(640.0, 360.0, 1.0);
	frameEnd();
	area.vh.scene.clearChanges();
}

function inContent(area: WindowArea, slot: NodeRef | null): boolean {
	if (slot === null) { return false; }
	const top = (area.vh.root as VoidNode).ref;
	let at: NodeRef | null = slot;
	while (at !== null) {
		const ref = at as NodeRef;
		if (ref.id.index === top.id.index && ref.id.generation === top.id.generation) { return true; }
		at = ref.parent();
	}
	return false;
}

function placesOf(area: WindowArea, layers: AreaLayer[]): string {
	const out: string[] = [];
	for (const layer of layers) { out.push(inContent(area, area.vh.layerSlot(layer.anchor)) ? "placed" : "held"); }
	return out.join(",");
}

function heldThroughErrored(scenes: NeonNode[], inText: boolean = false, emptyFallback: boolean = false): string {
	const log: string[] = [];
	const areas: WindowArea[] = [];
	const [fault, setFault] = createSignal(0);
	let again: (() => void) | null = null;
	const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		for (const scene of scenes) { scene(host, parent, before); }
		createRenderEffect<int32>(
			(p: int32 | null): int32 => fault(),
			(v: int32, p: int32 | null): Cleanup | null => { if (v === 1) { throw new Error("late"); } return null; },
		);
	};
	const held = Errored({
		children: content,
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => { again = reset; return emptyFallback ? (h: Host, p: HostNode, b: HostNode | null): void => {} : element(<Text>caught</Text>); },
	});
	const dispose = render(element(<Void>{inText ? element(<Text>{held}</Text>) : held}</Void>), windowHost(testWindow(log, areas)), windowNode("window"));
	const hub = areas[0].hub;
	const mounted = hub.layers().slice(0);
	const stage = (): string => {
		let same = hub.layers().length === mounted.length;
		for (let i = 0; same && i < mounted.length; i += 1) { same = hub.layers()[i] === mounted[i]; }
		const woke = log.indexOf("dirty") >= 0 || log.indexOf("frame") >= 0;
		return (same ? "same " : "other ") + placesOf(areas[0], hub.layers()) + (woke ? " woke" : " asleep");
	};
	const out: string[] = ["mount " + placesOf(areas[0], mounted)];
	drawn(areas[0]);
	log.length = 0;
	setFault(1);
	flush();
	out.push("held " + stage());
	drawn(areas[0]);
	log.length = 0;
	setFault(0);
	(again as () => void)();
	flush();
	out.push("reset " + stage());
	dispose();
	resetErrorHalt();
	return out.join(" | ");
}

test "an Errored fallback takes the Scene2D and Scene3D slots it holds out of the content, and a reset puts the same layers back" {
	const both = heldThroughErrored([element(<Scene2D />), element(<Scene3D />)]);
	assert both === "mount placed,placed | held same held,held woke | reset same placed,placed woke", both;
}

test "a held Scene3D alone leaves the content and wakes its area, though it puts nothing else in the area's tree" {
	const alone = heldThroughErrored([element(<Scene3D />)]);
	assert alone === "mount placed | held same held woke | reset same placed woke", alone;
}

test "an Errored that holds a Text takes the scenes inside it out of the content, and a reset puts them back" {
	const inText = heldThroughErrored([element(<Text>{element(<Scene2D />)}{element(<Scene3D />)}</Text>)]);
	assert inText === "mount placed,placed | held same held,held woke | reset same placed,placed woke", inText;
}

test "an Errored inside a Text takes the scenes it holds out of the paragraph, and a reset puts them back" {
	const inner = heldThroughErrored([element(<Scene2D />), element(<Scene3D />)], true);
	assert inner === "mount placed,placed | held same held,held woke | reset same placed,placed woke", inner;
}

test "an Errored inside a Text with an empty fallback wakes the area when it holds a scene and when a reset puts it back" {
	const inner = heldThroughErrored([element(<Scene3D />)], true, true);
	assert inner === "mount placed | held same held woke | reset same placed woke", inner;
}

test "a scene's place in the area takes no layout room" {
	const below = (scene: NeonNode): string => {
		const areas: WindowArea[] = [];
		const dispose = render(element(<Void style={{ flexDirection: "column", gap: 10 }}>{scene}<View style={{ height: 20 }} /></Void>), windowHost(testWindow([], areas)), windowNode("window"));
		try {
			const root = areas[0].vh.root as VoidNode;
			areas[0].vh.layout(640.0, 360.0);
			const place = areas[0].vh.tree.childrenOf(root)[0].ref.content();
			return "y=" + areas[0].vh.tree.childrenOf(root)[1].ref.local().y.toString() + " place=" + place.w.toString() + "x" + place.h.toString();
		} finally {
			dispose();
		}
	};
	const flat = below(element(<Scene2D />));
	assert flat === "y=0 place=0x0", "after a Scene2D: " + flat;
	const deep = below(element(<Scene3D />));
	assert deep === "y=0 place=0x0", "after a Scene3D: " + deep;
}

test "a Scene2D or Scene3D inside a Text mounts one layer, at a slot in the content" {
	const mounted = (scene: NeonNode): string => {
		const areas: WindowArea[] = [];
		const dispose = render(element(<Void><Text>{scene}</Text></Void>), windowHost(testWindow([], areas)), windowNode("window"));
		try {
			return areas[0].hub.layers().length.toString() + " " + placesOf(areas[0], areas[0].hub.layers());
		} finally {
			dispose();
		}
	};
	const flat = mounted(element(<Scene2D />));
	assert flat === "1 placed", "a Scene2D in a Text: " + flat;
	const deep = mounted(element(<Scene3D />));
	assert deep === "1 placed", "a Scene3D in a Text: " + deep;
}

function Probe(name: string, log: string[]): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const area = useContext(getVoidAreaContext()) as VoidArea;
		const anchor = layerAnchor(area, host, parent, before);
		const off: Unsubscribe = area.hub.addLayer({
			anchor,
			layout: (pixelWidth: int32, pixelHeight: int32): void => {},
			prepare: (pixelWidth: int32, pixelHeight: int32): void => {},
			draw: (): void => { log.push(name); },
		});
		onCleanup(off);
	};
}

function slotsOf(area: WindowArea, picks: int32[]): NodeRef[] {
	const layers = area.hub.layers();
	const out: NodeRef[] = [];
	for (const i of picks) { out.push(area.vh.layerSlot(layers[i].anchor) as NodeRef); }
	return out;
}

function dueNames(area: WindowArea, painted: NodeRef[], names: string[]): string {
	const out: string[] = [];
	for (const d of layersInPaintOrder(area.vh, area.hub.layers(), painted)) {
		out.push(names[area.hub.layers().indexOf(d.layer)]);
	}
	return out.join(",");
}

test "layers draw in the order the content painted their slots, and a slot it did not paint draws nothing" {
	const areas: WindowArea[] = [];
	const log: string[] = [];
	const dispose = render(element(<Void>{Probe("a", log)}<View />{Probe("b", log)}<View />{Probe("c", log)}</Void>), windowHost(testWindow([], areas)), windowNode("window"));
	try {
		const names = ["a", "b", "c"];
		const area = areas[0];
		const tree = dueNames(area, slotsOf(area, [0, 1, 2]), names);
		assert tree === "a,b,c", "in tree order: " + tree;
		const raised = dueNames(area, slotsOf(area, [2, 0, 1]), names);
		assert raised === "c,a,b", "c painted first, as a zIndex makes it: " + raised;
		const unpainted = dueNames(area, slotsOf(area, [0, 2]), names);
		assert unpainted === "a,c", "b's slot was not painted: " + unpainted;
	} finally {
		dispose();
	}
}

test "layers inside one Text share the slot after its paragraph and keep their span order" {
	const areas: WindowArea[] = [];
	const log: string[] = [];
	const [first, setFirst] = createSignal(false);
	const dispose = render(element(<Void><Text>{element(<Show when={first}>{Probe("t0", log)}</Show>)}{Probe("t1", log)}</Text></Void>), windowHost(testWindow([], areas)), windowNode("window"));
	try {
		const area = areas[0];
		setFirst(true);
		flush();
		const names = ["t1", "t0"];
		const slots = slotsOf(area, [0, 1]);
		assert slots[0].id.index === slots[1].id.index, "one slot per Text";
		const order = dueNames(area, [slots[0]], names);
		assert order === "t0,t1", "the later mounted t0 comes first in the paragraph: " + order;
		const text = area.vh.tree.childrenOf(area.vh.root as VoidNode)[0].ref;
		drawn(area);
		assert text.getChildIndex(slots[0]) === text.numChildren() - 1, "the slot paints after the paragraph label";
	} finally {
		dispose();
	}
}
