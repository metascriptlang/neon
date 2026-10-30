import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Rect, Label, Mask } from "../../src/components/scene2d";
import { Scene2D as VoidScene2D, NodeRef, local, filterChain, textStyle, text, content, scroll } from "../../../void/src/void2d/node";
import { prepare, drawScreen } from "../../../void/src/void2d/scene";
import { rgba, Camera, Filter, FilterKind, blurFilter, glowFilter, dropShadowFilter, noFilter } from "../../../void/src/void2d/types";
import { renderTargetsAlive, textWidth } from "../../../void/src/void2d/render";
import { FontId, addFont } from "../../../void/src/void2d/font";
import { TextStyle, Align } from "../../../void/src/void2d/textLayout";
import { setup2d, preparePipelines, drawCallCount, glyphPageCount } from "../../../void/src/void2d/draw";
import { BlendMode } from "../../../void/src/gpu/state";
import { gfxSetup, fbWidth, fbHeight, dpiScale } from "../../../void/src/host/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit } from "../../../void/src/gpu/door";

function soleFilter(n: NodeRef): Filter {
	const steps = n.filterChain().steps;
	if (steps.length > 1) { throw new Error(`a filter prop sets one step, and this node holds ${steps.length}`); }
	return steps.length === 0 ? noFilter() : steps[0];
}

@include("../../../void/src/host/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let subject: VoidScene2D | null = null;
let dispose: (() => void) | null = null;
let frames: int32 = 0;
const nodes: NodeRef[] = [];
const [x, setX] = createSignal<float32>(20.0);
const [pan, setPan] = createSignal<float32>(0.0);
const [radius, setRadius] = createSignal<float32>(2.0);
const [labelText, setText] = createSignal("Ag");
const [size, setSize] = createSignal<float32>(14.0);
const labels: NodeRef[] = [];
const masks: NodeRef[] = [];
const [clipWidth, setClipWidth] = createSignal<float32>(96.0);
const [scrollX, setScrollX] = createSignal<float32>(0.0);

const [filterPhase, setFilterPhase] = createSignal<int32>(0);
const [shift, setShift] = createSignal<float32>(4.0);

function currentFilter(): Filter {
	match (filterPhase()) {
		0 => { return blurFilter(radius()); }
		1 => { return glowFilter(rgba(0.0, 1.0, 0.0, 0.75), radius(), radius() - 1.0); }
		2 => { return dropShadowFilter(rgba(0.0, 0.0, 1.0, 0.5), radius(), shift(), shift()); }
		_ => { return noFilter(); }
	}
}

function loadedFont(): FontId {
	const loaded = addFont("../void/assets/font.ttf");
	if (!loaded.ok) { fail("font fixture refused"); process.exit(1); }
	return loaded.value;
}

function styled(font: FontId): TextStyle {
	return { font: font, size: 14.0, letterSpacing: 0.0, lineSpacing: 0.0,
		maxWidth: 0.0, align: Align.Left };
}

function viewport(): Camera {
	return { x: pan(), y: 0.0, zoom: 1.0, rotation: 0.0, anchorX: 0.0, anchorY: 0.0 };
}

function init(): void {
	gfxSetup(); setup2d(); preparePipelines([BlendMode.Alpha]);
	const font = loadedFont();
	const root = mockNode("root");
	dispose = render(element(<Void><Scene2D camera={viewport()}
		ref={(scene: VoidScene2D): void => { subject = scene; }}>
		<Mask width={clipWidth()} height={64.0} scrollX={scrollX()}
			scrollBounds={{ xMin: 0.0, yMin: 0.0, xMax: 200.0, yMax: 64.0 }}
			ref={(node: NodeRef): void => { masks.push(node); }}>
		<Rect width={32.0} height={32.0} color={rgba(1.0, 0.0, 0.0, 1.0)} filter={currentFilter()}
			local={{ x: x(), y: 20.0, scaleX: 1.0, scaleY: 1.0,
				rotation: 0.0, pivotX: 0.0, pivotY: 0.0 }}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
		<Label text={labelText()} size={size()} color={rgba(1.0, 1.0, 1.0, 1.0)}
			textStyle={styled(font)} ref={(node: NodeRef): void => { labels.push(node); }} />
		</Mask>
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
}

function fail(message: string): void {
	console.log("FAIL Scene2D device:", message);
	process.exit(1);
}

function frame(): void {
	const scene = subject;
	if (scene === null) { fail("consumer did not mount"); return; }
	if (frames > 0 && frames % 3 === 0) { setFilterPhase(frames / 3); }
	if (frames === 8) { setShift(8.0); }
	if (frames === 5) {
		setX(80.0); setPan(4.0); setRadius(3.0); setText("Neon"); setSize(18.0);
		setClipWidth(128.0); setScrollX(24.0);
	}
	flush();
	if (nodes.length !== 1 || nodes[0].local().x !== (frames < 5 ? 20.0 : 80.0)) {
		fail("consumer lost its reactive Rect"); return;
	}
	if (scene.cam.x !== (frames < 5 ? 0.0 : 4.0) ||
		soleFilter(nodes[0]).radius !== (frames >= 9 ? 0.0 : (frames < 5 ? 2.0 : 3.0))) {
		fail("consumer lost its reactive camera or filter"); return;
	}
	const active = soleFilter(nodes[0]);
	const expected = frames < 3 ? FilterKind.Blur : (frames < 6 ? FilterKind.Glow :
		(frames < 9 ? FilterKind.DropShadow : FilterKind.None));
	if (active.kind !== expected || (frames >= 3 && frames < 6 &&
		(active.gain !== (frames < 5 ? 1.0 : 2.0) || active.color.g !== 1.0)) ||
		(frames >= 6 && frames < 9 &&
		(active.offsetX !== (frames < 8 ? 4.0 : 8.0) || active.offsetY !== active.offsetX || active.color.b !== 1.0))) {
		fail("consumer lost its filter family/payload"); return;
	}
	if (labels.length !== 1 || labels[0].text() !== (frames < 5 ? "Ag" : "Neon") ||
		labels[0].textStyle().size !== (frames < 5 ? 14.0 : 18.0) ||
		labels[0].textWidth() <= 0.0) {
		fail("consumer lost its reactive real-font Label"); return;
	}
	if (masks.length !== 1 || masks[0].content().w !== (frames < 5 ? 96.0 : 128.0) ||
		masks[0].scroll().x !== (frames < 5 ? 0.0 : 24.0)) {
		fail("consumer lost its reactive Mask size or scroll"); return;
	}
	const dpi: float32 = dpiScale();
	scene.prepare((fbWidth() as float32) / dpi, (fbHeight() as float32) / dpi, dpi);
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.2, w: 1.0 });
	scene.drawScreen(); endPass(); commit();
	if (drawCallCount() < 1 || (frames < 9 && renderTargetsAlive() < 1) || glyphPageCount() < 1) {
		fail("filtered Rect did not submit a draw with a live target"); return;
	}
	frames++;
	if (frames === 12) {
		const cleanup = dispose;
		if (cleanup !== null) { cleanup(); }
		if (!scene.closed || renderTargetsAlive() !== 0) {
			fail("consumer did not close its scene and filter targets"); return;
		}
		console.log("PASS Scene2D device: 12 frames, reactive Rect/camera/Blur/Glow/DropShadow/None/Label/Mask, closed targets");
		process.exit(0);
	}
}

voidRun(192, 128, init, frame);
