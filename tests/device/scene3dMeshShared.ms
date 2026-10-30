import { createSignal, accessor } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Group, Mesh } from "../../src/components/scene3d";
import { MeshData, Box, addBox } from "../../../void/src/void3d/meshData";
import { DrawItem, liveMeshes } from "../../../void/src/void3d/draw";
import { refresh } from "../../../void/src/void3d/scene";
import { vec3 } from "../../../void/src/math/math3d";
import { gfxSetup } from "../../../void/src/host/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit, liveBuffers } from "../../../void/src/gpu/door";

@include("../../../void/src/host/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let handle: Scene3DHandle = null as unknown as Scene3DHandle;
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
let baseMeshes: int32 = 0;
let baseBuffers: int32 = 0;
let items: Vec<DrawItem> = [];
const [shown, setShown] = createSignal(true);
const [lastIsTall, setLastIsTall] = createSignal(true);

function fail(message: string): void {
	console.log("FAIL Mesh shared device:", message);
	process.exit(1);
}

function box(height: float32): MeshData {
	let data = MeshData.empty();
	const made = addBox(data, { base: vec3(0.0, 0.0, 0.0), size: vec3(1.0, height, 1.0), yaw: 0.0, tilt: 0.0,
		color: { red: 0.8, green: 0.4, blue: 0.2, alpha: 1.0 } });
	if (!made.ok) { fail("addBox"); unreachable; }
	return data;
}

const cube = box(1.0);
const tall = box(3.0);

function check(meshes: int32, nodes: int32, label: string): void {
	if (handle.context.liveMeshes() !== baseMeshes + meshes) { fail(label + ": uploaded meshes"); return; }
	if (refresh(handle.scene, items) !== nodes) { fail(label + ": mesh nodes"); return; }
}

function init(): void {
	gfxSetup();
	baseBuffers = liveBuffers();
	cleanup = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => {
		handle = value;
		baseMeshes = value.context.liveMeshes();
	}}>
		{Show({ when: accessor(() => shown()), children: element(<Group>
			<Mesh geometry={cube} />
			<Mesh geometry={cube} position={vec3(2.0, 0.0, 0.0)} />
			<Mesh geometry={box(1.0)} position={vec3(-2.0, 0.0, 0.0)} />
			<Mesh geometry={lastIsTall() ? tall : cube} position={vec3(0.0, 2.0, 0.0)} />
		</Group>) })}
	</Scene3D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
}

function frame(): void {
	if (frames === 0) { check(2, 4, "four Meshes over two geometries"); }
	if (frames === 1) {
		setLastIsTall(false);
		flush();
		check(1, 4, "swapping the last Mesh onto the shared cube");
	}
	if (frames === 2) {
		setShown(false);
		flush();
		check(0, 0, "unmounting every user");
		setLastIsTall(true);
		setShown(true);
		flush();
		check(2, 4, "remount");
	}
	beginScreenPass({ x: 0.02, y: 0.04, z: 0.1, w: 1.0 });
	endPass(); commit();
	frames += 1;
	if (frames === 4) {
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		if (!handle.context.closed || liveBuffers() !== baseBuffers) { fail("terminal GPU resource reclamation"); return; }
		console.log("PASS Mesh shared device: 4 Meshes, 2 geometries uploaded once each, swap/unmount/remount balanced");
		process.exit(0);
	}
}

voidRun(320, 240, init, frame);
