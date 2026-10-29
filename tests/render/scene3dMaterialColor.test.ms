import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Host, HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { NeonNode } from "../../src/render/hostTypes";
import { Void } from "../../src/components/primitives";
import { Scene3DHandle } from "../../src/components/scene3d/core";
import { Scene3D } from "../../src/components/scene3d/scene";
import { Mesh } from "../../src/components/scene3d/mesh";
import { createMaterial } from "../../src/components/scene3d/material";
import { NodeId3D } from "../../../void/src/void3d/scene";
import { DrawContext, MaterialId, NO_MESH } from "../../../void/src/void3d/draw";
import { MATERIAL_COLOR, PBR_UV_MATRIX } from "../../../void/src/void3d/gpu3d";
import { Color, rgba } from "../../../void/src/void2d/types";
import { added, litShape } from "../../../void/src/test/drawHelpers";

function uniformAt(context: DrawContext, material: MaterialId, at: int32): float32 {
	const block = context.materials[material.index].uniforms;
	return context.uniforms.values[block.offset + at];
}

function isWhite(context: DrawContext, material: MaterialId): boolean {
	for (let i: int32 = 0; i < 4; i += 1) {
		if (uniformAt(context, material, MATERIAL_COLOR + i) !== 1.0) { return false; }
	}
	return true;
}

function shownMaterial(handle: Scene3DHandle, node: NodeId3D): MaterialId {
	return handle.scene.meshes[handle.scene.nodes[node.index].payload].material;
}

function mountMesh(shadowed: boolean): [Scene3DHandle, NodeId3D, () => void] {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	let mesh = NO_MESH;
	const painted: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		element(<Mesh mesh={mesh} castShadow={shadowed}
			ref={(node: NodeId3D): void => { nodes.push(node); }} />)(host, parent, before);
	};
	const dispose = render(element(<Void>
		<Scene3D ref={(handle: Scene3DHandle): void => {
			refs.push(handle);
			mesh = added(handle.context, litShape());
		}}>{painted}</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	return [refs[0], nodes[0], dispose];
}

test "a Mesh without a material mounts and its block reads white at MATERIAL_COLOR" {
	const [handle, node, dispose] = mountMesh(false);
	try {
		assert isWhite(handle.context, shownMaterial(handle, node));
	} finally { dispose(); resetErrorHalt(); }
}

test "a Mesh with castShadow and no material mounts its shadow variant white at MATERIAL_COLOR" {
	const [handle, node, dispose] = mountMesh(true);
	try {
		assert isWhite(handle.context, shownMaterial(handle, node));
	} finally { dispose(); resetErrorHalt(); }
}

test "createMaterial blocks read white at MATERIAL_COLOR, a pbr one with the identity UV matrix" {
	const refs: Scene3DHandle[] = [];
	const made: Accessor<MaterialId>[] = [];
	const painted: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		made.push(createMaterial({ saturation: accessor((): float32 => 0.5) }));
		made.push(createMaterial({ roughness: accessor((): float32 => 0.5) }));
	};
	const dispose = render(element(<Void>
		<Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>{painted}</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	try {
		const context = refs[0].context;
		assert !context.materials[made[0]().index].program.pbr;
		assert isWhite(context, made[0]());
		assert context.materials[made[1]().index].program.pbr;
		assert isWhite(context, made[1]());
		assert uniformAt(context, made[1](), PBR_UV_MATRIX) === 1.0;
	} finally { dispose(); resetErrorHalt(); }
}

test "createMaterial color writes MATERIAL_COLOR on a lit and a pbr program and follows its signal" {
	const refs: Scene3DHandle[] = [];
	const made: Accessor<MaterialId>[] = [];
	const [tint, setTint] = createSignal<Color>(rgba(1.0, 0.5, 0.25, 0.75));
	const painted: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		made.push(createMaterial({ color: accessor((): Color => tint()) }));
		made.push(createMaterial({
			color: accessor((): Color => tint()),
			roughness: accessor((): float32 => 0.5),
		}));
	};
	const dispose = render(element(<Void>
		<Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>{painted}</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	try {
		const context = refs[0].context;
		assert !context.materials[made[0]().index].program.pbr;
		assert context.materials[made[1]().index].program.pbr;
		for (const material of made) {
			assert uniformAt(context, material(), MATERIAL_COLOR) === 1.0;
			assert uniformAt(context, material(), MATERIAL_COLOR + 1) === 0.5;
			assert uniformAt(context, material(), MATERIAL_COLOR + 2) === 0.25;
			assert uniformAt(context, material(), MATERIAL_COLOR + 3) === 0.75;
		}
		const first = made[0]();
		setTint(rgba(0.0, 1.0, 0.0, 1.0)); flush();
		assert made[0]() === first, "a colour change keeps the material";
		for (const material of made) {
			assert uniformAt(context, material(), MATERIAL_COLOR) === 0.0;
			assert uniformAt(context, material(), MATERIAL_COLOR + 1) === 1.0;
		}
	} finally { dispose(); resetErrorHalt(); }
}
