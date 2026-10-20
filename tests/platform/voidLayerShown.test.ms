import { Accessor, createSignal } from "../../src/core/signal";
import { createRenderEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Errored } from "../../src/macros/ui/flow";
import { render } from "../../src/render/host";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { AreaLayer } from "../../src/render/voidAreaHandle";
import { Void, View, Text } from "../../src/components/primitives";
import { Scene2D } from "../../src/components/scene2d";
import { Scene3D } from "../../src/components/scene3d";
import { VoidNode } from "../../src/platform/void/host";
import { AreaWindow, WindowArea, windowHost, windowNode } from "../../src/platform/void/windowHost";
import { FontId, addFont } from "../../../void/src/void2d/font";
import { clearChanges } from "../../../void/src/void2d/node";
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

function shownOf(layers: AreaLayer[]): string {
	const out: string[] = [];
	for (const layer of layers) { out.push(layer.shown() ? "shown" : "hidden"); }
	return out.join(",");
}

function heldThroughErrored(scenes: NeonNode[]): string {
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
	const dispose = render(element(<Void>
		{Errored({
			children: content,
			fallback: (err: Accessor<Error>, reset: () => void): NeonNode => { again = reset; return element(<Text>caught</Text>); },
		})}
	</Void>), windowHost(testWindow(log, areas)), windowNode("window"));
	const hub = areas[0].hub;
	const mounted = hub.layers().slice(0);
	const stage = (): string => {
		let same = hub.layers().length === mounted.length;
		for (let i = 0; same && i < mounted.length; i += 1) { same = hub.layers()[i] === mounted[i]; }
		const woke = log.indexOf("dirty") >= 0 || log.indexOf("frame") >= 0;
		return (same ? "same " : "other ") + shownOf(hub.layers()) + (woke ? " woke" : " asleep");
	};
	const out: string[] = ["mount " + shownOf(mounted)];
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

test "an Errored fallback hides the Scene2D and Scene3D layers it holds, and a reset shows the same layers" {
	const both = heldThroughErrored([element(<Scene2D />), element(<Scene3D />)]);
	assert both === "mount shown,shown | held same hidden,hidden woke | reset same shown,shown woke", both;
}

test "a held Scene3D alone hides and wakes its area, though it puts nothing else in the area's tree" {
	const alone = heldThroughErrored([element(<Scene3D />)]);
	assert alone === "mount shown | held same hidden woke | reset same shown woke", alone;
}

test "a scene's place in the area takes no layout room" {
	const below = (scene: NeonNode): string => {
		const areas: WindowArea[] = [];
		const dispose = render(element(<Void style={{ flexDirection: "column", gap: 10 }}>{scene}<View style={{ height: 20 }} /></Void>), windowHost(testWindow([], areas)), windowNode("window"));
		try {
			const root = areas[0].vh.root as VoidNode;
			areas[0].vh.layout(640.0, 360.0);
			const place = root.children[0].ref.content();
			return "y=" + root.children[1].ref.local().y.toString() + " place=" + place.w.toString() + "x" + place.h.toString();
		} finally {
			dispose();
		}
	};
	const flat = below(element(<Scene2D />));
	assert flat === "y=0 place=0x0", "after a Scene2D: " + flat;
	const deep = below(element(<Scene3D />));
	assert deep === "y=0 place=0x0", "after a Scene3D: " + deep;
}

test "a Scene2D or Scene3D inside a Text mounts as before, with no anchor, so its layer is always shown" {
	const mounted = (scene: NeonNode): string => {
		const areas: WindowArea[] = [];
		const dispose = render(element(<Void><Text>{scene}</Text></Void>), windowHost(testWindow([], areas)), windowNode("window"));
		try {
			return areas[0].hub.layers().length.toString() + " " + shownOf(areas[0].hub.layers());
		} finally {
			dispose();
		}
	};
	const flat = mounted(element(<Scene2D />));
	assert flat === "1 shown", "a Scene2D in a Text: " + flat;
	const deep = mounted(element(<Scene3D />));
	assert deep === "1 shown", "a Scene3D in a Text: " + deep;
}
