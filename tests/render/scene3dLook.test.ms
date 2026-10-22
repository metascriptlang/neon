import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show, Errored } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void, Text } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Light, Mesh } from "../../src/components/scene3d";
import { NodeId3D, LightKind } from "../../../void/src/void3d/scene";
import { MeshId, NO_MESH, NO_MATERIAL, releaseMesh } from "../../../void/src/void3d/draw";
import { freeRanges } from "../../../void/src/void3d/uniformPool";
import { Material, ShadowCasting } from "../../../void/src/void3d/material";
import { ToneMode } from "../../../void/src/void3d/renderer";
import { BloomSettings, natural } from "../../../void/src/void3d/bloom";
import { DirShadowMap, DEFAULT_SHADOW_BIAS } from "../../../void/src/void3d/dirShadowMap";
import { added, litShape } from "../../../void/src/test/drawHelpers";
import { approx } from "../../../void/src/test/helpers";

function frameRequests(outer: MockNode): int32 {
	let count: int32 = 0;
	for (const attr of outer.attrs) {
		if (attr.name === "frameRequested") { count += 1; }
	}
	return count;
}

function refused(app: () => NeonNode): string {
	let message = "";
	createRoot((dispose: () => void): void => {
		try {
			element(<Void>{app()}</Void>)(mockHost(), mockNode("root") as unknown as HostNode, null);
		} catch (error) { message = error.toString(); }
		finally { dispose(); resetErrorHalt(); }
	});
	return message;
}

test "an LDR Scene3D keeps Void's linear curve at exposure 1 and reserves no tone map" {
	const refs: Scene3DHandle[] = [];
	const dispose = render(element(<Void><Scene3D
		ref={(handle: Scene3DHandle): void => { refs.push(handle); }} /></Void>),
		mockHost(), mockNode("root") as unknown as HostNode);
	try {
		const core = refs[0].renderer.core;
		assert refs[0].renderer.toneMap === null && core.toneMode === ToneMode.Linear && core.exposure === 0.0;
		assert core.shadow === null;
	} finally { dispose(); }
	assert refs[0].renderer.closed && refs[0].context.closed;
}

test "hdr reserves the tone map at mount, defaults to the ACES curve and refuses a change" {
	const refs: Scene3DHandle[] = [];
	const [hdr, setHdr] = createSignal(true);
	const errors: Error[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void>{Errored({
		children: element(<Scene3D hdr={hdr()} ref={(handle: Scene3DHandle): void => { refs.push(handle); }} />),
		fallback: (error: Accessor<Error>, reset: () => void): NeonNode => {
			errors.push(error()); return element(<Text>hdr</Text>);
		},
	})}</Void>), mockHost(), root as unknown as HostNode);
	try {
		const renderer = refs[0].renderer;
		assert renderer.toneMap !== null && renderer.core.linearOutput;
		assert renderer.core.toneMode === ToneMode.Filmic;
		setHdr(false); flush();
		assert errors.length === 1 && errors[0].toString().includes("Scene3D: hdr is fixed at mount; remount the Scene3D to change it");
	} finally { dispose(); resetErrorHalt(); }
}

test "exposure is a multiplier and toneMapping a curve, both reactive and waking only their area" {
	const refs: Scene3DHandle[] = [];
	const [exposure, setExposure] = createSignal<float32>(2.0);
	const [mode, setMode] = createSignal<ToneMode>(ToneMode.Reinhard);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D exposure={exposure()} toneMapping={mode()}
		ref={(handle: Scene3DHandle): void => { refs.push(handle); }} /></Void>),
		mockHost(), root as unknown as HostNode);
	try {
		const core = refs[0].renderer.core;
		assert approx(core.exposure, Math.log(2.0) as float32) && core.toneMode === ToneMode.Reinhard;
		const requested = frameRequests(root.children[0]);
		setExposure(1.0); flush();
		assert core.exposure === 0.0 && frameRequests(root.children[0]) > requested;
		const later = frameRequests(root.children[0]);
		setMode(ToneMode.Neutral); flush();
		assert core.toneMode === ToneMode.Neutral && frameRequests(root.children[0]) > later;
	} finally { dispose(); }
}

test "exposure, bloom and hdr are refused by name before Void stops" {
	assert refused((): NeonNode => element(<Scene3D exposure={0.0} />)).includes("Scene3D: exposure must be a finite multiplier above 0");
	assert refused((): NeonNode => element(<Scene3D bloom={BloomSettings.natural()} />)).includes("Scene3D: bloom needs hdr");
	assert refused((): NeonNode => element(<Scene3D hdr={true} bloom={{ ...BloomSettings.natural(), maxMipDimension: 2 }} />))
		.includes("Scene3D: invalid bloom settings");
}

test "bloom turns on, changes and turns off on the HDR tone map" {
	const refs: Scene3DHandle[] = [];
	const [bloom, setBloom] = createSignal<BloomSettings | null>(BloomSettings.natural());
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D hdr={true} bloom={bloom()}
		ref={(handle: Scene3DHandle): void => { refs.push(handle); }} /></Void>),
		mockHost(), root as unknown as HostNode);
	try {
		const toneMap = refs[0].renderer.toneMap;
		if (toneMap === null) { throw new Error("hdr made no tone map"); }
		assert toneMap.bloom.isOn();
		const requested = frameRequests(root.children[0]);
		setBloom({ ...BloomSettings.natural(), intensity: 0.4 }); flush();
		const settings = toneMap.bloom.settings;
		assert settings !== null && (settings as BloomSettings).intensity === 0.4 && frameRequests(root.children[0]) > requested;
		setBloom(null); flush();
		assert !toneMap.bloom.isOn();
	} finally { dispose(); }
}

test "a directional Light casts through one DirShadowMap whose settings follow its props" {
	const refs: Scene3DHandle[] = [];
	const [cast, setCast] = createSignal(true);
	const [size, setSize] = createSignal(512);
	const [bias, setBias] = createSignal<float32>(DEFAULT_SHADOW_BIAS);
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		{Show({ when: accessor(() => shown()), children: element(
			<Light kind={LightKind.Directional} castShadow={cast()} shadowMapSize={size()} shadowBias={bias()} shadowOpacity={0.5} />
		) })}
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const context = refs[0].context;
		const core = refs[0].renderer.core;
		const shadow = core.shadow;
		if (shadow === null) { throw new Error("castShadow attached no shadow map"); }
		assert shadow.size === 512 && shadow.bias === DEFAULT_SHADOW_BIAS && shadow.opacity === 0.5;
		const free = context.uniforms.freeRanges();
		const requested = frameRequests(root.children[0]);
		setSize(2048); setBias(0.02); flush();
		assert core.shadow === shadow && shadow.size === 2048 && shadow.bias === 0.02;
		assert frameRequests(root.children[0]) > requested;
		setCast(false); flush();
		assert core.shadow === null && shadow.closed && context.uniforms.freeRanges() === free + 2;
		setCast(true); flush();
		const again = core.shadow;
		if (again === null) { throw new Error("castShadow did not attach again"); }
		assert !again.closed && again.size === 2048;
		setShown(false); flush();
		assert core.shadow === null && again.closed;
		setShown(true); flush();
		assert core.shadow !== null;
	} finally { dispose(); }
	assert refs[0].renderer.closed && refs[0].context.closed;
}

test "shadow props are refused by name on a point light, without castShadow and out of range" {
	assert refused((): NeonNode => element(<Scene3D><Light kind={LightKind.Point} castShadow={true} /></Scene3D>))
		.includes("Light: castShadow needs a Directional light; Void's shadow map follows the directional light");
	assert refused((): NeonNode => element(<Scene3D><Light kind={LightKind.Directional} shadowMapSize={1024} /></Scene3D>))
		.includes("Light: shadowMapSize, shadowBias and shadowOpacity need castShadow");
	assert refused((): NeonNode => element(<Scene3D><Light kind={LightKind.Directional} castShadow={true} shadowMapSize={0} /></Scene3D>))
		.includes("Light: invalid shadow settings");
	assert refused((): NeonNode => element(<Scene3D><Light kind={LightKind.Directional} castShadow={true} shadowOpacity={2.0} /></Scene3D>))
		.includes("Light: invalid shadow settings");
}

test "Mesh castShadow and receiveShadow pick a shadow variant of the default material" {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	let mesh: MeshId = NO_MESH;
	const [cast, setCast] = createSignal(true);
	const [receive, setReceive] = createSignal(false);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => {
		refs.push(handle); mesh = added(handle.context, litShape());
	}}>
		<Mesh mesh={mesh} castShadow={cast()} receiveShadow={receive()} ref={(node: NodeId3D): void => { nodes.push(node); }} />
		<Mesh mesh={mesh} castShadow={true} receiveShadow={false} ref={(node: NodeId3D): void => { nodes.push(node); }} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const context = refs[0].context;
		const scene = refs[0].scene;
		const materialOf = (node: NodeId3D): Material => context.materials[scene.meshes[scene.nodes[node.index].payload].material.index];
		const first = scene.meshes[scene.nodes[nodes[0].index].payload].material;
		assert first === scene.meshes[scene.nodes[nodes[1].index].payload].material, "one variant per flag pair";
		assert materialOf(nodes[0]).castShadows === ShadowCasting.On && !materialOf(nodes[0]).program.shadowed;
		setReceive(true); flush();
		assert materialOf(nodes[0]).castShadows === ShadowCasting.On && materialOf(nodes[0]).program.shadowed;
		setCast(false); setReceive(false); flush();
		assert materialOf(nodes[0]).castShadows === ShadowCasting.Off && !materialOf(nodes[0]).program.shadowed;
		assert releaseMesh(context, mesh).ok;
	} finally { dispose(); }
	assert refs[0].context.closed;
}

test "Mesh shadow flags beside an app material are refused by name" {
	assert refused((): NeonNode => element(<Scene3D ref={(handle: Scene3DHandle): void => {}}>
		<Mesh mesh={NO_MESH} material={NO_MATERIAL} castShadow={true} />
	</Scene3D>)).includes("Mesh: castShadow and receiveShadow need the default material");
}
