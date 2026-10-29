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
	DrawContext, MaterialId, NO_MESH, releaseMesh, releaseTexture,
} from "../../../void/src/void3d/draw";
import { MaterialKind } from "../../../void/src/void3d/material";
import { TextureId } from "../../../void/src/void3d/texture";
import { Texture } from "../../../void/src/gpu/texture";
import { addedOwner } from "../../../void/src/test/drawHelpers";
import {
	MATERIAL_SATURATION, MATERIAL_ALPHA_KILL, MATERIAL_COLOR, MATERIAL_PARALLAX, PBR_ROUGHNESS,
	PBR_OCCLUSION_STRENGTH, PBR_PARALLAX_STEPS,
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
		assert uniformAt(context, first, MATERIAL_COLOR) === 1.0 && uniformAt(context, first, MATERIAL_COLOR + 3) === 1.0, "a lit material is not tinted black";

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

test "createMaterial writes pbr roughness in place" {
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
	finally { held.splice(0, held.length); resetErrorHalt(); }
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

const held: TextureId[] = [];

function fixed(context: DrawContext, view: uint32): Accessor<TextureId> {
	const id = addedOwner(context, Texture.adopt(0, view, 1, 1));
	held.push(id);
	return accessor((): TextureId => id);
}

function mountedWith(build: (context: DrawContext) => MaterialProps): [Scene3DHandle, Accessor<MaterialId>[], () => void] {
	const refs: Scene3DHandle[] = [];
	const made: Accessor<MaterialId>[] = [];
	let props: MaterialProps = {};
	const painted: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		made.push(createMaterial(props));
	};
	const dispose = render(element(<Void>
		<Scene3D ref={(handle: Scene3DHandle): void => {
			refs.push(handle);
			props = build(handle.context);
		}}>{painted}</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	for (const id of held) {
		if (!releaseTexture(refs[0].context, id).ok) { throw new Error("fixture: a held texture did not release"); }
	}
	held.splice(0, held.length);
	return [refs[0], made, dispose];
}

function refusalWith(build: (context: DrawContext) => MaterialProps): string {
	let message = "";
	try {
		const [handle, made, dispose] = mountedWith(build);
		dispose();
	} catch (error) { message = error.message; }
	finally { held.splice(0, held.length); resetErrorHalt(); }
	return message;
}

function mapped(context: DrawContext): MaterialProps {
	return {
		texture: fixed(context, 70),
		metalRoughTexture: fixed(context, 71),
		occlusionTexture: fixed(context, 72),
	};
}

test "createMaterial names its pbr maps, and aoMapIntensity and occlusionChannel pick the occlusion read" {
	const [strength, setStrength] = createSignal<float32>(0.5);
	const [handle, made, dispose] = mountedWith((context: DrawContext): MaterialProps => ({
		...mapped(context),
		aoMapIntensity: accessor((): float32 => strength()),
		occlusionChannel: accessor((): int32 => 1),
	}));
	try {
		const context = handle.context;
		const material = made[0]();
		const key = context.materials[material.index].program;
		assert key.pbr && key.pbrMaps && key.occlusionUvB && !key.parallax;
		assert uniformAt(context, material, PBR_OCCLUSION_STRENGTH) === 0.5;
		setStrength(0.25); flush();
		assert made[0]() === material && uniformAt(context, material, PBR_OCCLUSION_STRENGTH) === 0.25;
	} finally { dispose(); resetErrorHalt(); }
	const [plain, plainMade, plainDispose] = mountedWith(mapped);
	try {
		const key = plain.context.materials[plainMade[0]().index].program;
		assert key.pbrMaps && !key.occlusionUvB;
		assert uniformAt(plain.context, plainMade[0](), PBR_OCCLUSION_STRENGTH) === 1.0;
	} finally { plainDispose(); resetErrorHalt(); }
}

test "createMaterial parallaxScale and parallaxSteps write Void's parallax floats on a mapped normal key" {
	const [scale, setScale] = createSignal<float32>(0.05);
	const [handle, made, dispose] = mountedWith((context: DrawContext): MaterialProps => ({
		...mapped(context),
		normalTexture: fixed(context, 73),
		parallaxScale: accessor((): float32 => scale()),
		parallaxSteps: accessor((): int32 => 12),
	}));
	try {
		const context = handle.context;
		const material = made[0]();
		const key = context.materials[material.index].program;
		assert key.parallax && key.pbrMaps && key.normalMap;
		assert uniformAt(context, material, MATERIAL_PARALLAX) === 0.05;
		assert uniformAt(context, material, PBR_PARALLAX_STEPS) === 12.0;
		setScale(0.1); flush();
		assert made[0]() === material && uniformAt(context, material, MATERIAL_PARALLAX) === 0.1;
	} finally { dispose(); resetErrorHalt(); }
	const [bare, bareMade, bareDispose] = mountedWith((context: DrawContext): MaterialProps => ({
		...mapped(context),
		normalTexture: fixed(context, 73),
		parallaxScale: accessor((): float32 => 0.05),
	}));
	try {
		assert uniformAt(bare.context, bareMade[0](), PBR_PARALLAX_STEPS) === 0.0, "0 is Void's 24 layers";
	} finally { bareDispose(); resetErrorHalt(); }
}

test "createMaterial refuses the maps, occlusion and parallax props a program cannot honour" {
	const one = refusalWith((context: DrawContext): MaterialProps => ({
		texture: fixed(context, 70), metalRoughTexture: fixed(context, 71),
	}));
	assert one.includes("createMaterial: metalRoughTexture and occlusionTexture go together"), one;
	const plain = refusalWith((context: DrawContext): MaterialProps => ({
		texture: fixed(context, 70), aoMapIntensity: accessor((): float32 => 0.5),
	}));
	assert plain.includes("createMaterial: aoMapIntensity and occlusionChannel need an occlusionTexture"), plain;
	const channel = refusalWith((context: DrawContext): MaterialProps => ({
		...mapped(context), occlusionChannel: accessor((): int32 => 2),
	}));
	assert channel.includes("createMaterial: occlusionChannel must be 0 or 1"), channel;
	const loud = refusalWith((context: DrawContext): MaterialProps => ({
		...mapped(context), aoMapIntensity: accessor((): float32 => 2.0),
	}));
	assert loud.includes("createMaterial: aoMapIntensity must be from 0 to 1"), loud;
	const unmapped = refusalWith((context: DrawContext): MaterialProps => ({
		texture: fixed(context, 70), normalTexture: fixed(context, 73),
		parallaxScale: accessor((): float32 => 0.05),
	}));
	assert unmapped.includes("createMaterial: parallaxScale needs metalRoughTexture"), unmapped;
	const flat = refusalWith((context: DrawContext): MaterialProps => ({
		...mapped(context), parallaxScale: accessor((): float32 => 0.05),
	}));
	assert flat.includes("createMaterial: parallaxScale needs metalRoughTexture"), flat;
	const steps = refusalWith((context: DrawContext): MaterialProps => ({
		...mapped(context), normalTexture: fixed(context, 73),
		parallaxSteps: accessor((): int32 => 12),
	}));
	assert steps.includes("createMaterial: parallaxSteps needs parallaxScale"), steps;
	const many = refusalWith((context: DrawContext): MaterialProps => ({
		...mapped(context), normalTexture: fixed(context, 73),
		parallaxScale: accessor((): float32 => 0.05), parallaxSteps: accessor((): int32 => 256),
	}));
	assert many.includes("createMaterial: parallaxSteps must be from 0 to 255"), many;
	const zero = refusalWith((context: DrawContext): MaterialProps => ({
		...mapped(context), normalTexture: fixed(context, 73),
		parallaxScale: accessor((): float32 => 0.0),
	}));
	assert zero.includes("createMaterial: parallaxScale must be a finite number above 0"), zero;
	const cast = refusalWith((context: DrawContext): MaterialProps => ({
		...mapped(context), normalTexture: fixed(context, 73),
		parallaxScale: accessor((): float32 => 0.05),
		kind: accessor((): MaterialKind => MaterialKind.AlphaKill),
		castShadow: accessor((): boolean => true),
	}));
	assert cast.includes("createMaterial: parallaxScale with MaterialKind.AlphaKill cannot cast"), cast;
}
