import { accessor, createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Billboards } from "../../src/components/scene3d";
import { DrawContext, MaterialId, NO_MATERIAL, addMaterial, releaseMaterial } from "../../../void/src/void3d/draw";
import { Material, MaterialKind } from "../../../void/src/void3d/material";
import { Program } from "../../../void/src/void3d/gpu3d";
import { BillboardInstance, ANCHOR_CENTER, ANCHOR_BOTTOM_CENTER } from "../../../void/src/void3d/billboard";
import { NodeId3D } from "../../../void/src/void3d/scene";
import { vec3 } from "../../../void/src/math/math3d";

function billboardMaterial(context: DrawContext): MaterialId {
	const made = addMaterial(context, Material.ofKind(Program.Billboard, MaterialKind.Alpha));
	if (!made.ok) { throw new Error("fixture: addMaterial: " + made.error.toString()); }
	return made.value;
}

function instance(x: float32): BillboardInstance {
	return {
		position: vec3(x, 0.0, 0.0), width: 1.0, height: 1.0, anchor: ANCHOR_CENTER,
		tile: { u: 0.0, v: 0.0, u2: 1.0, v2: 1.0 },
		color: { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 },
	};
}

function frameRequests(outer: MockNode): int32 {
	let n: int32 = 0;
	for (const a of outer.attrs) {
		if (a.name === "frameRequested") { n += 1; }
	}
	return n;
}

test "Billboards mount one mesh node that draws nothing until a frame uploads, and unmount frees it" {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	let material = NO_MATERIAL;
	const [shown, setShown] = createSignal(true);
	const root: MockNode = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); material = billboardMaterial(value.context); }}>
			{Show({ when: accessor(() => shown()), children: element(
				<Billboards instances={[instance(0.0), instance(1.0)]} material={material}
					ref={(value: NodeId3D): void => { nodes.push(value); }} />
			) })}
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const handle = refs[0];
	const baseline = handle.context.liveMeshes();
	assert handle.scene.isLive(nodes[0]), "the billboard node mounts";
	const row = handle.scene.nodes[nodes[0].index].payload;
	const mesh = handle.scene.meshes[row].mesh;
	assert handle.context.meshes[mesh.index].instanceBuffer === 0 && handle.context.meshes[mesh.index].instanceCount === 0, "no GPU buffer before a frame";
	assert handle.context.meshHolders[mesh.index] === 1, "only the node holds the mesh";
	setShown(false);
	flush();
	assert !handle.scene.isLive(nodes[0]) && handle.context.liveMeshes() === baseline - 1, "unmount frees the node and its mesh";
	setShown(true);
	flush();
	assert handle.context.liveMeshes() === baseline, "a remount holds exactly one mesh again";
	const released = releaseMaterial(handle.context, material);
	assert released.ok;
}

test "Billboards ask for a frame when their instances change and none while idle" {
	const [list, setList] = createSignal<BillboardInstance[]>([instance(0.0)]);
	const root: MockNode = mockNode("root");
	let material = NO_MATERIAL;
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { material = billboardMaterial(value.context); }}>
			<Billboards instances={list()} material={material} />
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const outer = root.children[0];
	const mounted = frameRequests(outer);
	flush();
	assert frameRequests(outer) === mounted, "idle billboards ask for nothing";
	setList([instance(0.0), { ...instance(2.0), anchor: ANCHOR_BOTTOM_CENTER }]);
	flush();
	assert frameRequests(outer) > mounted, "new instances ask for a frame";
}
