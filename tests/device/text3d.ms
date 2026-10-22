// Text3D through the Scene3D layer of a Void area, on the GPU.
//   msc build tests/device/text3d.ms --output=out/text3d && out/text3d
// Exits 0 once a label redrew, rescaled, faced the camera, was replaced and released its GPU resources;
// glyph atlas pages are process-wide and stay.

import { accessor, createSignal } from "../../src/core/signal";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { AreaHub } from "../../src/render/voidAreaHandle";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Camera3D, Text3D } from "../../src/components/scene3d";
import { NodeId3D, Object3D, syncWorld } from "../../../void/src/void3d/scene";
import { Mat4, Vec3, vec3 } from "../../../void/src/math/math3d";
import { rgba } from "../../../void/src/void2d/types";
import { liveTextures, liveMaterials, liveMeshes } from "../../../void/src/void3d/draw";
import { setup2d } from "../../../void/src/void2d/draw";
import { gfxSetup, fbWidth, fbHeight } from "../../../void/src/sokol/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit, liveImages, liveViews } from "../../../void/src/gpu/door";
import { glyphAtlas } from "../../../void/src/void2d/labelText";
import { pageCount } from "../../../void/src/void2d/glyphAtlas";

@include("../../../void/src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let handle: Scene3DHandle = null as unknown as Scene3DHandle;
let hub: AreaHub = null as unknown as AreaHub;
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
let baseImages: int32 = 0;
let baseViews: int32 = 0;
let basePages: int32 = 0;
let baseTextures: int32 = 0;
let baseMaterials: int32 = 0;
let baseMeshes: int32 = 0;
let shortWidth: float32 = 0.0;
const flat: NodeId3D[] = [];
const faced: NodeId3D[] = [];
const [text, setText] = createSignal("Hi");
const [size, setSize] = createSignal<float32>(16.0);
const [perUnit, setPerUnit] = createSignal<float32>(100.0);
const [shown, setShown] = createSignal(true);
const [yaw, setYaw] = createSignal<float32>(0.0);

function fail(message: string): void {
	console.log("FAIL Text3D device:", message);
	process.exit(1);
}

function labelOf(group: NodeId3D): Object3D {
	const row = handle.scene.nodes[group.index];
	if (row.children.length !== 1) { fail("a Text3D group holds one label node, got " + row.children.length.toString()); }
	return handle.scene.nodes[row.children[0]];
}

function near(a: float32, b: float32): boolean {
	return Math.abs(a - b) < 0.001;
}

function init(): void {
	gfxSetup();
	setup2d();
	baseImages = liveImages(); baseViews = liveViews(); basePages = glyphAtlas.pageCount();
	const root: MockNode = mockNode("root");
	cleanup = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => {
		handle = value;
		baseTextures = value.context.liveTextures();
		baseMaterials = value.context.liveMaterials();
		baseMeshes = value.context.liveMeshes();
	}}>
		<Camera3D active={true} position={vec3(0.0, 0.0, 5.0)} yaw={yaw()} />
		{Show({ when: accessor(() => shown()), children: element(<>
			<Text3D text={text()} size={size()} color={rgba(1.0, 0.8, 0.2, 1.0)} pixelsPerUnit={perUnit()}
				position={vec3(-1.0, 0.0, 0.0)} ref={(node: NodeId3D): void => { flat.push(node); }} />
			<Text3D text="faced" billboard={true} position={vec3(1.0, 0.5, 0.0)}
				ref={(node: NodeId3D): void => { faced.push(node); }} />
		</>) })}
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	hub = mockAreaHub(root.children[0]);
}

function drawFrame(): void {
	const width = fbWidth();
	const height = fbHeight();
	hub.layoutLayers(width, height);
	hub.prepareLayers(hub.layers(), width, height);
	beginScreenPass({ x: 0.05, y: 0.05, z: 0.1, w: 1.0 });
	hub.drawLayers((layer): void => {});
	endPass();
	commit();
}

function expectLabels(count: int32, what: string): void {
	const context = handle.context;
	if (context.liveTextures() !== baseTextures + count || context.liveMaterials() !== baseMaterials + count ||
		context.liveMeshes() !== baseMeshes + count) {
		fail(what + ": textures/materials/meshes " + context.liveTextures().toString() + "/" +
			context.liveMaterials().toString() + "/" + context.liveMeshes().toString());
	}
}

function frame(): void {
	drawFrame();
	frames += 1;
	if (frames === 1) {
		expectLabels(2, "two mounted labels");
		shortWidth = labelOf(flat[0]).local.scale.x;
		if (!(shortWidth > 0.0)) { fail("label scale"); }
		setText("Hello from Neon");
		flush();
	} else if (frames === 2) {
		const wide = labelOf(flat[0]).local.scale.x;
		if (!(wide > shortWidth * 2.0)) { fail("a longer text did not widen the quad: " + shortWidth.toString() + " -> " + wide.toString()); }
		syncWorld(handle.scene);
		const label = labelOf(faced[0]);
		const world: Mat4 = label.world;
		if (!near(world.m41, 1.0) || !near(world.m42, 0.5) || !near(world.m13, 0.0)) { fail("billboard pose before yaw"); }
		setYaw(0.7);
		flush();
	} else if (frames === 3) {
		syncWorld(handle.scene);
		const world: Mat4 = labelOf(faced[0]).world;
		const across = Math.sqrt(world.m11 * world.m11 + world.m12 * world.m12 + world.m13 * world.m13) as float32;
		if (!near(world.m13 / across, -Math.sin(0.7) as float32) && !near(world.m13 / across, Math.sin(0.7) as float32)) {
			fail("billboard did not turn with the camera: m13 " + (world.m13 / across).toString());
		}
		const flatWorld: Mat4 = labelOf(flat[0]).world;
		if (!near(flatWorld.m13, 0.0)) { fail("a flat label turned with the camera"); }
		let message = "";
		try { setSize(0.0); flush(); } catch (error) { message = error.message; }
		finally { resetErrorHalt(); }
		if (message !== "Text3D: size must be positive") { fail("size refusal: " + message); }
		setSize(24.0);
		flush();
	} else if (frames === 4) {
		expectLabels(2, "after a size change");
		const before = labelOf(flat[0]).local.scale.x;
		setPerUnit(50.0);
		flush();
		expectLabels(2, "pixelsPerUnit replacement released the old label");
		if (flat.length !== 1) { fail("replacement called ref again"); }
		shortWidth = before;
	} else if (frames === 5) {
		const wide = labelOf(flat[0]).local.scale.x;
		if (!near(wide, shortWidth * 2.0)) { fail("half the pixels per unit doubles the width: " + shortWidth.toString() + " -> " + wide.toString()); }
		setShown(false);
		flush();
		expectLabels(0, "unmounted labels");
	} else if (frames === 6) {
		setShown(true);
		flush();
		expectLabels(2, "remounted labels");
		if (flat.length !== 2 || faced.length !== 2 || handle.scene.isLive(flat[0])) { fail("remount identity"); }
	} else if (frames === 8) {
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		const pages = glyphAtlas.pageCount() - basePages;
		if (!handle.scene.closed || !handle.context.closed || liveImages() !== baseImages + pages ||
			liveViews() !== baseViews + pages) {
			fail("terminal GPU resource reclamation: images " + liveImages().toString() + "/" + baseImages.toString() +
				" views " + liveViews().toString() + "/" + baseViews.toString());
		}
		console.log("PASS Text3D device: redraw rescale, billboard, refusal, replacement, remount, closed GPU resources");
		process.exit(0);
	}
}

voidRun(320, 240, init, frame);
