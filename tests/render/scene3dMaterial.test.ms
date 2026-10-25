import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { Host, HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { NeonNode } from "../../src/render/hostTypes";
import { Void } from "../../src/components/primitives";
import { Scene3DHandle } from "../../src/components/scene3d/core";
import { Scene3D } from "../../src/components/scene3d/scene";
import { Mesh } from "../../src/components/scene3d/mesh";
import { createMaterial, MaterialProps } from "../../src/components/scene3d/material";
import { NodeId3D } from "../../../void/src/void3d/scene";
import {
	DrawContext, MaterialId, NO_MESH, releaseMesh,
} from "../../../void/src/void3d/draw";
import { MaterialKind } from "../../../void/src/void3d/material";
import {
	MATERIAL_SATURATION, MATERIAL_ALPHA_KILL, PBR_ROUGHNESS,
} from "../../../void/src/void3d/gpu3d";
import { Color, Vec2, rgba } from "../../../void/src/void2d/types";
import { added, litShape } from "../../../void/src/test/drawHelpers";

function uniformAt(context: DrawContext, material: MaterialId, at: int32): float32 {
	const block = context.materials[material.index].uniforms;
	return context.uniforms.values[block.offset + at];
}

function shownMaterial(handle: Scene3DHandle, node: NodeId3D): MaterialId {
	return handle.scene.meshes[handle.scene.nodes[node.index].payload].material;
}

test "createMaterial owns a lit material: values in place, a key change swaps, unmount releases" {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	const made: Accessor<MaterialId>[] = [];
	let mesh = NO_MESH;
	const [saturation, setSaturation] = createSignal<float32>(0.0);
	const [kind, setKind] = createSignal(MaterialKind.Opaque);
	const [shown, setShown] = createSignal(true);
	const painted: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const material = createMaterial({
			saturation: accessor((): float32 => saturation()),
			kind: accessor((): MaterialKind => kind()),
		});
		made.push(material);
		element(<Mesh mesh={mesh} material={material()}
			ref={(node: NodeId3D): void => { nodes.push(node); }} />)(host, parent, before);
	};
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(handle: Scene3DHandle): void => {
			refs.push(handle);
			mesh = added(handle.context, litShape());
		}}>
			{Show({ when: accessor(() => shown()), children: painted })}
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	try {
		const handle = refs[0];
		const context = handle.context;
		const first = made[0]();
		assert context.hasMaterial(first), "created on mount";
		assert shownMaterial(handle, nodes[0]) === first;
		assert context.materialHolders[first.index] === 2 && context.materialPins[first.index] === 1;
		assert !context.materials[first.index].program.cutout;

		setSaturation(-1.0); flush();
		assert made[0]() === first, "a value change keeps the material";
		assert uniformAt(context, first, MATERIAL_SATURATION) === -1.0;
		assert context.materialHolders[first.index] === 2;

		setKind(MaterialKind.AlphaKill); flush();
		const second = made[0]();
		assert second !== first, "a program key change makes a new material";
		assert context.materials[second.index].program.cutout;
		assert uniformAt(context, second, MATERIAL_ALPHA_KILL) === 0.5;
		assert uniformAt(context, second, MATERIAL_SATURATION) === -1.0, "values carry over";
		assert shownMaterial(handle, nodes[0]) === second, "Mesh swaps to the new material";
		assert !context.hasMaterial(first), "the old material is released";
		assert context.materialHolders[second.index] === 2;
		assert nodes.length === 1, "the swap keeps the node";

		setShown(false); flush();
		assert !context.hasMaterial(second), "unmount releases the material";
		assert releaseMesh(context, mesh).ok;
	} finally {
		dispose(); resetErrorHalt();
	}
}

test "createMaterial writes pbr roughness in place and refuses a colour on a lit material" {
	const refs: Scene3DHandle[] = [];
	const made: Accessor<MaterialId>[] = [];
	const [roughness, setRoughness] = createSignal<float32>(0.5);
	const painted: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		made.push(createMaterial({ roughness: accessor((): float32 => roughness()) }));
	};
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>{painted}</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	try {
		const context = refs[0].context;
		const material = made[0]();
		assert context.materials[material.index].program.pbr;
		assert uniformAt(context, material, PBR_ROUGHNESS) === 0.5;
		setRoughness(0.25); flush();
		assert made[0]() === material && uniformAt(context, material, PBR_ROUGHNESS) === 0.25;
	} finally {
		dispose(); resetErrorHalt();
	}
	let message = "";
	try {
		const coloured: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			const material = createMaterial({
				color: accessor((): Color => rgba(1.0, 0.0, 0.0, 1.0)),
			});
		};
		const cleanup = render(element(<Void><Scene3D>{coloured}</Scene3D></Void>),
			mockHost(), mockNode("root") as unknown as HostNode);
		cleanup();
	} catch (error) { message = error.message; }
	finally { resetErrorHalt(); }
	assert message.includes("createMaterial: color"), message;
}

function mountError(props: MaterialProps): string {
	let message = "";
	try {
		const made: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			const material = createMaterial(props);
		};
		const cleanup = render(element(<Void><Scene3D>{made}</Scene3D></Void>),
			mockHost(), mockNode("root") as unknown as HostNode);
		cleanup();
	} catch (error) { message = error.message; }
	finally { resetErrorHalt(); }
	return message;
}

test "createMaterial names what Void cannot build before it reserves anything" {
	const unlit = mountError({ unlit: accessor((): boolean => true) });
	assert unlit.includes("createMaterial: unlit needs a texture"), unlit;
	const glow = mountError({ emissive: accessor((): Color => rgba(1.0, 1.0, 1.0, 1.0)) });
	assert glow.includes("createMaterial: emissive and emissiveIntensity need an emissiveTexture"), glow;
	const scroll = mountError({ uvScroll: accessor((): Vec2 => ({ x: 0.1, y: 0.0 })) });
	assert scroll.includes("createMaterial: uvRepeat, uvOffset and uvScroll need a texture"), scroll;
	const smooth = mountError({ roughness: accessor((): float32 => 0.0) });
	assert smooth.includes("createMaterial: roughness 0"), smooth;
}

test "createMaterial refuses to run outside a Scene3D" {
	let message = "";
	try {
		const lost: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			const material = createMaterial({});
		};
		const cleanup = render(element(<Void>{lost}</Void>),
			mockHost(), mockNode("root") as unknown as HostNode);
		cleanup();
	} catch (error) { message = error.message; }
	finally { resetErrorHalt(); }
	assert message === "createMaterial: mount inside Scene3D within Void", message;
}
