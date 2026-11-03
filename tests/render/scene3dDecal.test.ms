import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { contextGeneration } from "../../../void/src/gpu/door";
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
import { DrawContext, releaseTexture, buryDoomed } from "../../../void/src/void3d/draw";
import { TextureId, NO_TEXTURE } from "../../../void/src/void3d/texture";
import { Texture } from "../../../void/src/gpu/texture";
import { addedOwner } from "../../../void/src/test/drawHelpers";

function texture(context: DrawContext, view: uint32): TextureId {
	const id = addedOwner(context, Texture.adopt(0, view, 1, 1));
	onCleanup((): void => {
		if (!releaseTexture(context, id).ok) { throw new Error("fixture: a held texture did not release"); }
		buryDoomed(context, contextGeneration() + 1);
	});
	return id;
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

test "Decals in one scene share one unit box and the last one out releases it" {
	const refs: Scene3DHandle[] = [];
	const [first, setFirst] = createSignal(true);
	const [second, setSecond] = createSignal(true);
	let baseline: int32 = -1;
	let projected: TextureId = NO_TEXTURE;
	const dispose = render(element(<Void>
		<Scene3D ref={(handle: Scene3DHandle): void => {
			refs.push(handle);
			baseline = handle.context.liveMeshes();
			projected = texture(handle.context, 70);
		}}>
			{Show({ when: accessor(() => first()), children: element(<Decal map={accessor((): TextureId => projected)} />) })}
			{Show({ when: accessor(() => second()), children: element(<Decal map={accessor((): TextureId => projected)} />) })}
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	const context = refs[0].context;
	assert context.liveMeshes() - baseline == 1, "two decals hold " + (context.liveMeshes() - baseline).toString() + " box meshes";
	setFirst(false); flush();
	assert context.liveMeshes() - baseline == 1, "one decal left holds " + (context.liveMeshes() - baseline).toString() + " box meshes";
	setSecond(false); flush();
	assert context.liveMeshes() - baseline == 0, "no decal left holds " + (context.liveMeshes() - baseline).toString() + " box meshes";
	dispose(); resetErrorHalt();
}
