import { accessor, createSignal } from "../../src/core/signal";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Mesh } from "../../src/components/scene3d";
import {
	NodeId3D, NO_NODE_ID, nodeCount, isLive,
} from "../../../void/src/void3d/scene";
import {
	DrawContext, MeshId, MaterialId, NO_MATERIAL, NO_MESH, addMaterial, releaseMaterial,
	releaseMesh, closeContext, hasMaterial, hasMesh,
} from "../../../void/src/void3d/draw";
import { Material, Phase } from "../../../void/src/void3d/material";
import { Program } from "../../../void/src/void3d/gpu3d";
import { RenderState } from "../../../void/src/gpu/state";
import { added, litShape } from "../../../void/src/test/drawHelpers";

function plainMaterial(context: DrawContext): MaterialId {
	const made = addMaterial(context,
		Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque));
	if (!made.ok) { throw new Error("fixture: addMaterial: " + made.error.toString()); }
	return made.value;
}

function releaseBorrowed(
	context: DrawContext,
	mesh: MeshId,
	materials: Span<MaterialId>,
): void {
	for (const material of materials) {
		if (context.hasMaterial(material) &&
			context.materialHolders[material.index] > context.materialPins[material.index]) {
			const released = releaseMaterial(context, material);
			if (!released.ok) { throw new Error("fixture: release material"); }
		}
	}
	if (context.hasMesh(mesh) && context.meshHolders[mesh.index] > context.meshPins[mesh.index]) {
		const released = releaseMesh(context, mesh);
		if (!released.ok) { throw new Error("fixture: release mesh"); }
	}
}

function frameRequests(outer: MockNode): int32 {
	let count: int32 = 0;
	for (const attr of outer.attrs) {
		if (attr.name === "frameRequested") { count += 1; }
	}
	return count;
}

test "Mesh material replacement keeps node identity and balances borrowed sibling pins" {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	let mesh = NO_MESH;
	let first = NO_MATERIAL;
	let second = NO_MATERIAL;
	const [choice, setChoice] = createSignal(0);
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(handle: Scene3DHandle): void => {
			refs.push(handle);
			mesh = added(handle.context, litShape());
			first = plainMaterial(handle.context);
			second = plainMaterial(handle.context);
		}}>
			{Show({ when: accessor(() => shown()), children: element(<>
				<Mesh mesh={mesh} material={choice() % 2 === 0 ? first : second}
					ref={(node: NodeId3D): void => { nodes.push(node); }} />
				<Mesh mesh={mesh} material={first}
					ref={(node: NodeId3D): void => { nodes.push(node); }} />
			</>) })}
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const outer = root.children[0];
	try {
		const handle = refs[0];
		const context = handle.context;
		const scene = handle.scene;
		assert context.materialHolders[first.index] === 3;
		assert context.materialHolders[second.index] === 1;
		const initialRequests = frameRequests(root.children[0]);
		setChoice(1); flush();
		assert scene.meshes[scene.nodes[nodes[0].index].payload].material === second;
		assert scene.meshes[scene.nodes[nodes[1].index].payload].material === first;
		assert context.materialHolders[first.index] === 2;
		assert context.materialHolders[second.index] === 2;
		assert context.materialPins[first.index] === 1 && context.materialPins[second.index] === 1;
		assert frameRequests(root.children[0]) > initialRequests;
		setChoice(3); flush();
		assert context.materialHolders[second.index] === 2, "same id must not add a hold";
		setChoice(2); flush();
		assert scene.meshes[scene.nodes[nodes[0].index].payload].material === first;
		assert context.materialHolders[first.index] === 3;
		assert context.materialHolders[second.index] === 1;
		assert nodes.length === 2 && scene.nodeCount() === 3, "updates never remount";
		setShown(false); flush();
		assert !scene.isLive(nodes[0]) && !scene.isLive(nodes[1]);
		assert context.hasMaterial(first) && context.hasMaterial(second);
		assert context.materialHolders[first.index] === 1;
		assert context.materialHolders[second.index] === 1;
		assert context.meshHolders[mesh.index] === 1;
		assert releaseMaterial(context, first).ok && releaseMaterial(context, second).ok;
		assert releaseMesh(context, mesh).ok;
	} finally {
		releaseBorrowed(refs[0].context, mesh, [first, second]);
		dispose(); resetErrorHalt();
	}
	const requests = frameRequests(outer);
	setChoice(1); flush();
	assert refs[0].context.closed && refs[0].scene.closed;
	assert frameRequests(outer) === requests, "disposed material effect stays stopped";
}

test "Mesh rejects stale and foreign materials without losing binding and retries failed values" {
	const refs: Scene3DHandle[] = [];
	let mesh = NO_MESH;
	let first = NO_MATERIAL;
	let second = NO_MATERIAL;
	let stale = NO_MATERIAL;
	let node = NO_NODE_ID;
	const elsewhere = DrawContext.withUniformCapacity(0);
	const foreign = plainMaterial(elsewhere);
	const [choice, setChoice] = createSignal(0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => {
		refs.push(handle);
		mesh = added(handle.context, litShape());
		first = plainMaterial(handle.context);
		second = plainMaterial(handle.context);
		stale = plainMaterial(handle.context);
		const released = releaseMaterial(handle.context, stale);
		if (!released.ok) { throw new Error("fixture: release stale material"); }
	}}>
		<Mesh mesh={mesh}
			material={choice() === 0 ? first :
				choice() === 2 ? foreign : choice() === 4 ? second : stale}
			ref={(value: NodeId3D): void => { node = value; }} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const handle = refs[0];
		for (const choice of [1, 3, 2]) {
			let message = "";
			const requests = frameRequests(root.children[0]);
			try { setChoice(choice); flush(); }
			catch (error) { message = error.toString(); }
			finally { resetErrorHalt(); }
			assert message.includes("Mesh: setMaterialOf failed:");
			assert message.includes(choice === 2 ? "ForeignMaterial" : "StaleMaterial");
			assert handle.scene.meshes[handle.scene.nodes[node.index].payload].material === first;
			assert handle.context.materialHolders[first.index] === 2;
			assert handle.context.materialHolders[second.index] === 1;
			assert handle.context.materialPins[first.index] === 1;
			assert handle.context.materialPins[second.index] === 0;
			assert elsewhere.materialHolders[foreign.index] === 1;
			assert frameRequests(root.children[0]) === requests, "failed apply does not invalidate";
		}
		setChoice(4); flush();
		assert handle.scene.meshes[handle.scene.nodes[node.index].payload].material === second;
		assert handle.context.materialHolders[first.index] === 1;
		assert handle.context.materialHolders[second.index] === 2;
		setChoice(0); flush();
		assert handle.scene.meshes[handle.scene.nodes[node.index].payload].material === first;
		assert handle.context.materialHolders[first.index] === 2;
		assert handle.context.materialHolders[second.index] === 1;
		assert releaseMaterial(handle.context, first).ok;
		assert releaseMaterial(handle.context, second).ok;
		assert releaseMesh(handle.context, mesh).ok;
	} finally {
		releaseBorrowed(refs[0].context, mesh, [first, second]);
		dispose();
		const released = releaseMaterial(elsewhere, foreign);
		if (!released.ok) { throw new Error("fixture: release foreign material"); }
		closeContext(elsewhere); resetErrorHalt();
	}
	assert refs[0].context.materialHolders[first.index] === 0;
	assert refs[0].context.materialHolders[second.index] === 0;
}

test "Mesh replacement releases last material pin and same id keeps the replacement alive" {
	const refs: Scene3DHandle[] = [];
	let mesh = NO_MESH;
	let first = NO_MATERIAL;
	let second = NO_MATERIAL;
	const [choice, setChoice] = createSignal(0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => {
		refs.push(handle);
		mesh = added(handle.context, litShape());
		first = plainMaterial(handle.context);
		second = plainMaterial(handle.context);
	}}>
		<Mesh mesh={mesh} material={choice() === 0 ? first : second} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const context = refs[0].context;
		assert releaseMaterial(context, first).ok;
		assert context.hasMaterial(first) && context.materialHolders[first.index] === 1;
		setChoice(1); flush();
		assert !context.hasMaterial(first) && context.materialHolders[first.index] === 0;
		assert releaseMaterial(context, second).ok;
		assert context.hasMaterial(second) && context.materialHolders[second.index] === 1;
		setChoice(2); flush();
		assert context.hasMaterial(second) && context.materialHolders[second.index] === 1;
		assert releaseMesh(context, mesh).ok;
	} finally {
		releaseBorrowed(refs[0].context, mesh, [first, second]);
		dispose(); resetErrorHalt();
	}
	assert refs[0].context.materialHolders[second.index] === 0;
}

test "Mesh owns its shared default material until scene disposal without consuming caller mesh" {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	let mesh = NO_MESH;
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => {
		refs.push(handle); mesh = added(handle.context, litShape());
	}}>
		{Show({ when: accessor(() => shown()), children: element(<>
			<Mesh mesh={mesh} ref={(node: NodeId3D): void => { nodes.push(node); }} />
			<Mesh mesh={mesh} ref={(node: NodeId3D): void => { nodes.push(node); }} />
		</>) })}
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	let material = NO_MATERIAL;
	try {
		const handle = refs[0];
		material = handle.scene.meshes[handle.scene.nodes[nodes[0].index].payload].material;
		const sibling = handle.scene.meshes[handle.scene.nodes[nodes[1].index].payload];
		assert sibling.material === material;
		assert handle.context.materialHolders[material.index] === 3;
		assert handle.context.materialPins[material.index] === 2;
		setShown(false); flush();
		assert handle.context.hasMaterial(material);
		assert handle.context.materialHolders[material.index] === 1;
		assert handle.context.materialPins[material.index] === 0;
		assert handle.context.hasMesh(mesh) && handle.context.meshHolders[mesh.index] === 1;
		assert releaseMesh(handle.context, mesh).ok;
	} finally {
		releaseBorrowed(refs[0].context, mesh, []);
		dispose(); resetErrorHalt();
	}
	assert refs[0].context.materialHolders[material.index] === 0;
	assert refs[0].context.uniforms.closed;
}

