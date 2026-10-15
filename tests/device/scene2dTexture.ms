import { accessor, createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Sprite } from "../../src/components/scene2d";
import { Scene2D as VoidScene2D, NodeRef, content, isLive } from "../../../void/src/void2d/node";
import { prepare, drawScreen } from "../../../void/src/void2d/scene";
import { Tile, tile } from "../../../void/src/void2d/types";
import { Texture, fromPixels, close } from "../../../void/src/gpu/texture";
import { setup2d, drawCallCount } from "../../../void/src/void2d/draw";
import { gfxSetup, fbWidth, fbHeight, dpiScale } from "../../../void/src/sokol/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit } from "../../../void/src/gpu/door";

@include("../../../void/src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let subject: VoidScene2D | null = null;
let dispose: (() => void) | null = null;
let first: Texture | null = null;
let second: Texture | null = null;
let frames: int32 = 0;
const nodes: NodeRef[] = [];
const [replacement, setReplacement] = createSignal(false);
const [shown, setShown] = createSignal(true);

function fail(message: string): void {
	console.log("FAIL Scene2D texture device:", message);
	process.exit(1);
}

function selectedTile(): Tile {
	const texture = replacement() ? second : first;
	if (texture === null) { fail("texture was not uploaded"); unreachable; }
	return tile(texture, 2.0, 2.0);
}

function init(): void {
	gfxSetup(); setup2d();
	const red: Vec<uint32> = [0xFF0000FF as uint32, 0xFF0000FF as uint32,
		0xFF0000FF as uint32, 0xFF0000FF as uint32];
	const green: Vec<uint32> = [0xFF00FF00 as uint32, 0xFF00FF00 as uint32,
		0xFF00FF00 as uint32, 0xFF00FF00 as uint32];
	const a = Texture.fromPixels(red, 2, 2, true);
	const b = Texture.fromPixels(green, 2, 2, true);
	if (!a.ok || !b.ok) { fail("real texture upload refused"); return; }
	first = a.value; second = b.value;
	const root = mockNode("root");
	// Parked: ~/metascript/.inbox/compiler/2026-10-07-captured-const-nullable-struct-loses-narrowing.md.
	dispose = render(element(<Void><Scene2D
		ref={(scene: VoidScene2D): void => { subject = scene; }}>
		{Show({ when: accessor(() => shown()), children: element(
			<Sprite tile={selectedTile()} width={32.0} height={32.0}
				ref={(node: NodeRef): void => { nodes.push(node); }} />
		) })}
		<Sprite tile={tile(a.value, 2.0, 2.0)} width={16.0} height={16.0} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
}

function frame(): void {
	const scene = subject;
	const a = first;
	const b = second;
	if (scene === null || a === null || b === null) { fail("consumer did not mount"); return; }
	if (frames === 3) { setReplacement(true); }
	if (frames === 6) { setShown(false); }
	if (frames === 8) { setShown(true); }
	if (a.closed || b.closed || a.view === 0 || b.view === 0) {
		fail("Sprite closed or lost its borrowed uploaded owner"); return;
	}
	if (frames < 6 || frames >= 8) {
		const node = nodes[nodes.length - 1];
		if (!node.isLive() || node.content().tile.source.texture !== (frames < 3 ? a : b)) {
			fail("Tile replacement did not bind its owner"); return;
		}
	}
	if (frames >= 6 && nodes[0].isLive()) { fail("removed Sprite stayed live"); return; }
	if (frames >= 8 && nodes.length !== 2) { fail("Sprite did not remount once"); return; }
	const dpi: float32 = dpiScale();
	scene.prepare((fbWidth() as float32) / dpi, (fbHeight() as float32) / dpi, dpi);
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.2, w: 1.0 });
	scene.drawScreen(); endPass(); commit();
	if (drawCallCount() < 1) { fail("uploaded Sprite did not submit a draw"); return; }
	frames++;
	if (frames === 12) {
		const cleanup = dispose;
		if (cleanup !== null) { cleanup(); }
		if (!scene.closed || nodes[1].isLive() || a.closed || b.closed) {
			fail("terminal cleanup stole a texture owner or left a node live"); return;
		}
		a.close(); b.close();
		if (!a.closed || !b.closed) { fail("caller could not close its owners"); return; }
		console.log("PASS Scene2D texture device: 12 frames, upload, replacement, remount, caller close");
		process.exit(0);
	}
}

voidRun(192, 128, init, frame);
