import { element } from "../../src/macros/ui/element";
import { flush } from "../../src/core/runtime";
import { render } from "../../src/render/host";
import { HostNode } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";
import { AreaLayer, AreaPointerKind } from "../../src/render/voidAreaHandle";
import { View, Pressable } from "../../src/components/primitives";
import { createVoidHostWith, VoidHost, VoidNode } from "../../src/platform/void/host";
import { Scene2D } from "../../../void/src/void2d/node";
import { create } from "../../../void/src/void2d/scene";
import { Style } from "../../src/render/style";
import { rgba } from "../../../void/src/void2d/types";
import { FontId, addFont } from "../../../void/src/void2d/font";

const FONT_PATH = "../void/assets/font.ttf";

function loadedFont(): FontId {
	const r = addFont(FONT_PATH);
	if (!r.ok) { throw new Error("the test font did not load from " + FONT_PATH + "; run from the Neon checkout root beside ../void"); }
	return r.value;
}

function host(): VoidHost {
	return createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), loadedFont());
}

function top(vh: VoidHost): VoidNode {
	return vh.tree.childrenOf(vh.root as VoidNode)[0];
}

// A layer that fills the window and records what reaches it, standing in for a Scene3D area.
function layerHeard(vh: VoidHost, heard: string[]): AreaLayer {
	const anchor = vh.host.createText("");
	const layer: AreaLayer = {
		anchor: { node: anchor, inText: false },
		layout: (w: int32, h: int32): void => {},
		prepare: (w: int32, h: int32): void => {},
		draw: (): void => {},
		hit: (x: float32, y: float32, kind: AreaPointerKind, e: NeonEvent): boolean => {
			heard.push(kind.toString());
			return true;
		},
	};
	vh.setLayers((): AreaLayer[] => [layer]);
	return layer;
}

// The layer's slot goes before the first child of the top view, or after the last when `after`.
function placed(vh: VoidHost, layer: AreaLayer, after: boolean): void {
	const parent = top(vh) as unknown as HostNode;
	const kids = vh.tree.childrenOf(top(vh));
	vh.host.insertBefore(parent, layer.anchor.node as HostNode, after ? null : kids[0] as unknown as HostNode);
}

function overHud(mode: string | null, after: boolean = false): string {
	const vh = host();
	const heard: string[] = [];
	const style: Style = { width: 100, height: 100 };
	if (mode !== null) { style.pointerEvents = mode; }
	render(element(<View style={{ width: 200, height: 100 }}><View style={style} /></View>), vh.host, vh.root);
	placed(vh, layerHeard(vh, heard), after);
	vh.layout(200.0, 100.0);
	vh.pointerDown(50.0, 50.0, 1 as int32);
	vh.pointerUp(50.0, 50.0, 1 as int32);
	vh.pointerMove(50.0, 50.0, 0 as int32, false);
	vh.wheel(50.0, 50.0, 0.0, 10.0, 0);
	return heard.join(",");
}

test "a View over a layer, with no handler, keeps the click, move and wheel from it" {
	assert overHud(null) === "", "auto blocks: " + overHud(null);
}

test "a View with pointerEvents none or box-none lets the click through to the layer" {
	assert overHud("none") === "Button,Button,Motion,Wheel", "none: " + overHud("none");
	assert overHud("box-none") === "Button,Button,Motion,Wheel", "box-none: " + overHud("box-none");
}

test "a View painted before the layer's slot does not block it" {
	assert overHud(null, true) === "Button,Button,Motion,Wheel", "under the layer: " + overHud(null, true);
}

test "a Pressable over a layer still gets its press and the layer hears nothing" {
	const vh = host();
	const heard: string[] = [];
	let pressed = 0;
	render(element(<View style={{ width: 200, height: 100 }}><Pressable style={{ width: 100, height: 100 }} onPress={(): void => { pressed = pressed + 1; }} /></View>), vh.host, vh.root);
	placed(vh, layerHeard(vh, heard), false);
	vh.layout(200.0, 100.0);
	vh.pointerDown(50.0, 50.0, 1 as int32);
	vh.pointerUp(50.0, 50.0, 1 as int32);
	flush();
	assert pressed === 1, "pressed " + pressed.toString();
	assert heard.length === 0, "layer heard " + heard.join(",");
}
