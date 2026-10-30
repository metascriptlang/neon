// RenderTexture: a Scene2D drawn into a texture that a sibling Mesh shows, through the Scene3D layer, on the GPU.
//   msc build tests/device/renderTexture.ms --output=out/renderTexture && out/renderTexture
// Exits 0 once the target redrew only on change, survived a resize, remounted and released its GPU resources.
// Glyph atlas pages (the Rect's mask too) are process-wide and stay.
// Context loss is not exercised: gpu/door loseContext simulates it only on the D3D11 and Android bridges.

import { accessor, createSignal } from "../../src/core/signal";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { AreaHub } from "../../src/render/voidAreaHandle";
import { Void } from "../../src/components/primitives";
import { Scene2D, Rect } from "../../src/components/scene2d";
import { Scene3D, Scene3DHandle, Camera3D, Mesh, RenderTexture, RenderTextureHandle } from "../../src/components/scene3d";
import { NodeId3D } from "../../../void/src/void3d/scene";
import { MeshData } from "../../../void/src/void3d/meshData";
import { MaterialId, liveTextures, liveMaterials, hasTexture, hasMaterial } from "../../../void/src/void3d/draw";
import { ANCHOR_CENTER } from "../../../void/src/void3d/billboard";
import { labelQuad } from "../../../void/src/void3d/worldLabel";
import { vec3 } from "../../../void/src/math/math3d";
import { Color, rgba } from "../../../void/src/void2d/types";
import { Scene2D as VoidScene2D } from "../../../void/src/void2d/node";
import { glyphAtlas } from "../../../void/src/void2d/labelText";
import { pageCount } from "../../../void/src/void2d/glyphAtlas";
import { setup2d, preparePipelines } from "../../../void/src/void2d/draw";
import { BlendMode } from "../../../void/src/gpu/state";
import { gfxSetup, fbWidth, fbHeight } from "../../../void/src/host/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit, liveImages, liveViews, originTopLeft } from "../../../void/src/gpu/door";

@include("../../../void/src/host/bridge.h");
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
let drawnAt: int32 = 0;
let screen: MaterialId = { store: 0, index: 0, generation: 0 };
const handles: RenderTextureHandle[] = [];
const insides: VoidScene2D[] = [];
const meshes: NodeId3D[] = [];
const [shown, setShown] = createSignal(true);
const [width, setWidth] = createSignal<int32>(128);
const [fill, setFill] = createSignal<Color>(rgba(1.0, 0.0, 0.0, 1.0));

function fail(message: string): void {
	console.log("FAIL RenderTexture device:", message);
	process.exit(1);
}

function quad(): MeshData {
	const made = labelQuad(ANCHOR_CENTER, !originTopLeft());
	if (!made.ok) { fail("quad"); unreachable; }
	return made.value;
}

function init(): void {
	gfxSetup();
	setup2d();
	preparePipelines([BlendMode.Alpha]);
	baseImages = liveImages(); baseViews = liveViews(); basePages = glyphAtlas.pageCount();
	const root: MockNode = mockNode("root");
	cleanup = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => {
		handle = value;
		baseTextures = value.context.liveTextures();
		baseMaterials = value.context.liveMaterials();
	}}>
		<Camera3D active={true} position={vec3(0.0, 0.0, 3.0)} />
		{Show({ when: accessor(() => shown()), children: element(<>
			<RenderTexture width={width()} height={64}
				ref={(value: RenderTextureHandle): void => { handles.push(value); screen = value.material; }}>
				<Scene2D clear={rgba(0.0, 0.0, 1.0, 1.0)} ref={(value: VoidScene2D): void => { insides.push(value); }}>
					<Rect width={32.0} height={32.0} color={fill()} />
				</Scene2D>
			</RenderTexture>
			<Mesh geometry={quad()} material={screen} ref={(node: NodeId3D): void => { meshes.push(node); }} />
		</>) })}
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	hub = mockAreaHub(root.children[0]);
}

function drawFrame(): void {
	const w = fbWidth();
	const h = fbHeight();
	hub.layoutLayers(w, h);
	hub.prepareLayers(hub.layers(), w, h);
	beginScreenPass({ x: 0.05, y: 0.05, z: 0.1, w: 1.0 });
	hub.drawLayers((layer): void => {});
	endPass();
	commit();
}

function inside(): VoidScene2D {
	return insides[insides.length - 1];
}

function expectOwned(count: int32, what: string): void {
	const context = handle.context;
	if (context.liveTextures() !== baseTextures + count || context.liveMaterials() !== baseMaterials + count) {
		fail(what + ": textures/materials " + context.liveTextures().toString() + "/" + context.liveMaterials().toString());
	}
}

function frame(): void {
	try { drawFrame(); } catch (error) { fail("frame " + frames.toString() + ": " + error.message); }
	frames += 1;
	const context = handle.context;
	if (frames === 1) {
		expectOwned(1, "mounted");
		const own = handles[0];
		if (handles.length !== 1 || !context.hasTexture(own.texture) || !context.hasMaterial(own.material)) { fail("handle"); }
		if (context.materials[own.material.index].texture.index !== own.texture.index) { fail("material samples another texture"); }
		const node = meshes[0];
		if (handle.scene.meshes[handle.scene.nodes[node.index].payload].material.index !== own.material.index) {
			fail("the sibling Mesh does not show the RenderTexture material");
		}
		drawnAt = inside().context.preparedFrame as int32;
	} else if (frames === 2) {
		if ((inside().context.preparedFrame as int32) !== drawnAt) { fail("an unchanged subtree redrew its target"); }
		setFill(rgba(0.0, 1.0, 0.0, 1.0));
		flush();
	} else if (frames === 3) {
		if ((inside().context.preparedFrame as int32) === drawnAt) { fail("a changed subtree did not redraw its target"); }
		drawnAt = inside().context.preparedFrame as int32;
		let message = "";
		try { setWidth(0); flush(); } catch (error) { message = error.message; }
		finally { resetErrorHalt(); }
		if (message !== "RenderTexture: width and height must be positive") { fail("size refusal: " + message); }
		setWidth(256);
		flush();
	} else if (frames === 4) {
		if (inside().context.fbW !== 256.0 || !context.hasTexture(handles[0].texture)) { fail("resize: fbW " + inside().context.fbW.toString()); }
		setShown(false);
		flush();
		expectOwned(0, "unmounted");
	} else if (frames === 5) {
		setShown(true);
		flush();
		expectOwned(1, "remounted");
		if (handles.length !== 2 || insides.length !== 2) { fail("remount"); }
	} else if (frames === 8) {
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		const pages = glyphAtlas.pageCount() - basePages;
		if (!handle.scene.closed || !handle.context.closed || liveImages() !== baseImages + pages ||
			liveViews() !== baseViews + pages) {
			fail("terminal GPU resource reclamation: images " + liveImages().toString() + "/" + baseImages.toString() +
				" views " + liveViews().toString() + "/" + baseViews.toString());
		}
		console.log("PASS RenderTexture device: on-demand redraw, refusal, resize, remount, closed GPU resources");
		process.exit(0);
	}
}

voidRun(320, 240, init, frame);
