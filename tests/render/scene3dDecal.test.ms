import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { Host, HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { NeonNode } from "../../src/render/hostTypes";
import { Void } from "../../src/components/primitives";
import { Scene3DHandle } from "../../src/components/scene3d/core";
import { Scene3D } from "../../src/components/scene3d/scene";
import { Decal, DecalProps, DecalNormalFade } from "../../src/components/scene3d/decal";
import { NodeId3D, NO_NODE_ID } from "../../../void/src/void3d/scene";
import { DrawContext, MaterialId } from "../../../void/src/void3d/draw";
import { Phase } from "../../../void/src/void3d/material";
import { TextureId, NO_TEXTURE } from "../../../void/src/void3d/texture";
import { Texture } from "../../../void/src/gpu/texture";
import { addedOwner } from "../../../void/src/test/drawHelpers";
import {
	Program, DECAL_COLOR, DECAL_FADE_START, DECAL_FADE_END, DECAL_FADE_POWER, DECAL_EMISSIVE, DECAL_CENTERED,
	DECAL_GAMMA_CORRECT, DECAL_AUTO_ALPHA, DECAL_TONE_MAPPED, DECAL_NORMAL_FADE_START, DECAL_NORMAL_FADE_END,
	DECAL_NORMAL_FADE,
} from "../../../void/src/void3d/gpu3d";
import { Color, rgba } from "../../../void/src/void2d/types";
import { vec3 } from "../../../void/src/math/math3d";

function block(context: DrawContext, material: MaterialId, at: int32): float32 {
	return context.uniforms.values[context.materials[material.index].uniforms.offset + at];
}

function shown(handle: Scene3DHandle, node: NodeId3D): MaterialId {
	return handle.scene.meshes[handle.scene.nodes[node.index].payload].material;
}

function texture(context: DrawContext, view: uint32): TextureId {
	return addedOwner(context, Texture.adopt(0, view, 1, 1));
}

function mountedWith(build: (context: DrawContext) => DecalProps): [Scene3DHandle, NodeId3D[], () => void] {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	let props: DecalProps = { map: accessor((): TextureId => texture(refs[0].context, 70)) };
	const painted: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Decal({ ...props, ref: (node: NodeId3D): void => { nodes.push(node); } })(host, parent, before);
	};
	const dispose = render(element(<Void>
		<Scene3D ref={(handle: Scene3DHandle): void => {
			refs.push(handle);
			props = build(handle.context);
		}}>{painted}</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	return [refs[0], nodes, dispose];
}

function fixed(context: DrawContext, view: uint32): Accessor<TextureId> {
	const id = texture(context, view);
	return accessor((): TextureId => id);
}

function refusalWith(build: (context: DrawContext) => DecalProps): string {
	let message = "";
	try {
		const [handle, nodes, dispose] = mountedWith(build);
		dispose();
	} catch (error) { message = error.message; }
	finally { resetErrorHalt(); }
	return message;
}

test "Decal mounts a box node of Void's decal program holding DecalOverlay's defaults" {
	const [handle, nodes, dispose] = mountedWith((context: DrawContext): DecalProps => ({
		map: fixed(context, 70),
		position: accessor(() => vec3(1.0, 2.0, 3.0)),
		scale: accessor(() => vec3(2.0, 0.5, 4.0)),
	}));
	try {
		const context = handle.context;
		const material = shown(handle, nodes[0]);
		const used = context.materials[material.index];
		assert used.program.program === Program.Decal && used.phase === Phase.Decal;
		assert used.texture.isTexture() && used.texture.index === 0;
		const local = handle.scene.nodes[nodes[0].index].local;
		assert local.position.y === 2.0 && local.scale.z === 4.0, "NodeProps place the box";
		for (let i = 0; i < 4; i++) { assert block(context, material, DECAL_COLOR + i) === 1.0; }
		assert block(context, material, DECAL_FADE_START) === 0.0 && block(context, material, DECAL_FADE_END) === 1.0;
		assert block(context, material, DECAL_FADE_POWER) === 1.0 && block(context, material, DECAL_EMISSIVE) === 0.0;
		assert block(context, material, DECAL_CENTERED) === 1.0 && block(context, material, DECAL_GAMMA_CORRECT) === 0.0;
		assert block(context, material, DECAL_AUTO_ALPHA) === 1.0 && block(context, material, DECAL_TONE_MAPPED) === 1.0;
		assert block(context, material, DECAL_NORMAL_FADE) === 0.0;
	} finally { dispose(); resetErrorHalt(); }
}

test "Decal writes color, fade, emissive and the normal fade into the block" {
	const [handle, nodes, dispose] = mountedWith((context: DrawContext): DecalProps => ({
		map: fixed(context, 70),
		color: accessor((): Color => rgba(0.5, 0.25, 0.75, 0.5)),
		fadeStart: accessor((): float32 => 0.25), fadeEnd: accessor((): float32 => 0.75),
		fadePower: accessor((): float32 => 2.0), emissive: accessor((): float32 => 0.5),
		normalFade: accessor((): DecalNormalFade => ({ start: 0.25, end: 0.5 })),
	}));
	try {
		const context = handle.context;
		const material = shown(handle, nodes[0]);
		assert block(context, material, DECAL_COLOR) === 0.5 && block(context, material, DECAL_COLOR + 1) === 0.25;
		assert block(context, material, DECAL_COLOR + 2) === 0.75 && block(context, material, DECAL_COLOR + 3) === 0.5;
		assert block(context, material, DECAL_FADE_START) === 0.25 && block(context, material, DECAL_FADE_END) === 0.75;
		assert block(context, material, DECAL_FADE_POWER) === 2.0 && block(context, material, DECAL_EMISSIVE) === 0.5;
		assert block(context, material, DECAL_NORMAL_FADE) === 1.0;
		assert block(context, material, DECAL_NORMAL_FADE_START) === 0.25 && block(context, material, DECAL_NORMAL_FADE_END) === 0.5;
	} finally { dispose(); resetErrorHalt(); }
}

test "Decal afterToneMap draws in the after-tone-map phase with the tone-map flag off" {
	const [handle, nodes, dispose] = mountedWith((context: DrawContext): DecalProps => ({
		map: fixed(context, 70), afterToneMap: accessor((): boolean => true),
	}));
	try {
		const material = shown(handle, nodes[0]);
		assert handle.context.materials[material.index].phase === Phase.DecalAfterToneMap;
		assert block(handle.context, material, DECAL_TONE_MAPPED) === 0.0;
	} finally { dispose(); resetErrorHalt(); }
}

test "Decal values change in place, and map or afterToneMap swap the material" {
	const [color, setColor] = createSignal<Color>(rgba(1.0, 1.0, 1.0, 1.0));
	const [fadeEnd, setFadeEnd] = createSignal<float32>(1.0);
	const [normal, setNormal] = createSignal<DecalNormalFade | null>(null);
	const [after, setAfter] = createSignal<boolean>(false);
	const [view, setView] = createSignal<uint32>(70);
	const [at, setAt] = createSignal(vec3(0.0, 0.0, 0.0));
	const [handle, nodes, dispose] = mountedWith((context: DrawContext): DecalProps => ({
		map: accessor((): TextureId => texture(context, view())),
		color: accessor((): Color => color()), fadeEnd: accessor((): float32 => fadeEnd()),
		normalFade: accessor((): DecalNormalFade => normal() as DecalNormalFade),
		afterToneMap: accessor((): boolean => after()),
		position: accessor(() => at()),
	}));
	try {
		const context = handle.context;
		const first = shown(handle, nodes[0]);
		assert nodes.length === 1;
		setColor(rgba(0.5, 1.0, 1.0, 1.0)); setFadeEnd(0.5); flush();
		assert shown(handle, nodes[0]) === first, "a value change keeps the material";
		assert block(context, first, DECAL_COLOR) === 0.5 && block(context, first, DECAL_FADE_END) === 0.5;
		setAt(vec3(0.0, 4.0, 0.0)); flush();
		assert handle.scene.nodes[nodes[0].index].local.position.y === 4.0, "position moves the node";
		setAfter(true); flush();
		const second = shown(handle, nodes[0]);
		assert second !== first && !context.hasMaterial(first), "a pass change swaps and releases the old material";
		assert context.materials[second.index].phase === Phase.DecalAfterToneMap;
		assert block(context, second, DECAL_COLOR) === 0.5 && block(context, second, DECAL_TONE_MAPPED) === 0.0;
		setView(71); flush();
		const third = shown(handle, nodes[0]);
		assert third !== second && !context.hasMaterial(second), "a map change swaps and releases the old material";
		assert context.materials[third.index].texture !== context.materials[second.index].texture;
	} finally { dispose(); resetErrorHalt(); }
}

test "Decal unmount removes the node and releases the material" {
	const [shownNow, setShownNow] = createSignal(true);
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	const materials: MaterialId[] = [];
	const painted: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Decal({
			map: accessor((): TextureId => texture(refs[0].context, 70)),
			ref: (node: NodeId3D): void => { nodes.push(node); materials.push(shown(refs[0], node)); },
		})(host, parent, before);
	};
	const dispose = render(element(<Void>
		<Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
			{Show({ when: accessor(() => shownNow()), children: painted })}
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	try {
		assert refs[0].scene.isLive(nodes[0]) && refs[0].context.hasMaterial(materials[0]);
		setShownNow(false); flush();
		assert !refs[0].scene.isLive(nodes[0]), "the node is removed";
		assert !refs[0].context.hasMaterial(materials[0]), "the material is released";
	} finally { dispose(); resetErrorHalt(); }
}

test "Decal refuses outside a Scene3D, an untextured map, and what Void cannot honour" {
	let message = "";
	try {
		const lost: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			Decal({ map: accessor((): TextureId => NO_TEXTURE) })(host, parent, before);
		};
		const cleanup = render(element(<Void>{lost}</Void>), mockHost(), mockNode("root") as unknown as HostNode);
		cleanup();
	} catch (error) { message = error.message; }
	finally { resetErrorHalt(); }
	assert message === "Decal: mount inside Scene3D within Void", message;

	const bare = refusalWith((context: DrawContext): DecalProps => ({ map: accessor((): TextureId => NO_TEXTURE) }));
	assert bare.includes("Decal: map must be a texture"), bare;
	const target = refusalWith((context: DrawContext): DecalProps => ({
		map: fixed(context, 70), mesh: accessor((): NodeId3D => NO_NODE_ID),
	}));
	assert target.includes("Decal: mesh has no counterpart"), target;
	const offset = refusalWith((context: DrawContext): DecalProps => ({
		map: fixed(context, 70), polygonOffsetFactor: accessor((): float32 => -10.0),
	}));
	assert offset.includes("Decal: polygonOffsetFactor has no counterpart"), offset;
	const depth = refusalWith((context: DrawContext): DecalProps => ({
		map: fixed(context, 70), depthTest: accessor((): boolean => true),
	}));
	assert depth.includes("Decal: depthTest has no counterpart"), depth;
	const debug = refusalWith((context: DrawContext): DecalProps => ({
		map: fixed(context, 70), debug: accessor((): boolean => true),
	}));
	assert debug.includes("Decal: debug has no counterpart"), debug;
	const empty = refusalWith((context: DrawContext): DecalProps => ({
		map: fixed(context, 70), fadeStart: accessor((): float32 => 1.0),
	}));
	assert empty.includes("Decal: fadeEnd must be above fadeStart"), empty;
	const flat = refusalWith((context: DrawContext): DecalProps => ({
		map: fixed(context, 70), normalFade: accessor((): DecalNormalFade => ({ start: 0.5, end: 0.5 })),
	}));
	assert flat.includes("Decal: normalFade end must be above its start"), flat;
	const nan = refusalWith((context: DrawContext): DecalProps => ({
		map: fixed(context, 70), emissive: accessor((): float32 => Number.NaN as float32),
	}));
	assert nan.includes("Decal: emissive must be finite"), nan;
}
