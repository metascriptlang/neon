import { createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Light, SpotLight, DirectionalLight, PointLight } from "../../src/components/scene3d";
import { LightKind, collectLights } from "../../../void/src/void3d/scene";
import { LIGHT_UNIFORM_LENGTH } from "../../../void/src/void3d/gpu3d";
import { DirShadowMap, ShadowKind, ShadowSamplingKind } from "../../../void/src/void3d/dirShadowMap";
import { approx } from "../../../void/src/test/helpers";

const QUARTER: float32 = 0.7853981634;

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

function held(map: DirShadowMap | null): DirShadowMap {
	if (map === null) { throw new Error("no shadow map attached"); }
	return map as DirShadowMap;
}

test "a spot and a point light each attach their own map, beside the sun's, with R3F's soft default" {
	const refs: Scene3DHandle[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		<DirectionalLight castShadow={true} />
		<SpotLight angle={QUARTER} penumbra={0.5} distance={8.0} castShadow={true} shadowMapSize={256} />
		<PointLight castShadow={true} shadowMapSize={128} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const core = refs[0].renderer.core;
		const sun = held(core.shadow);
		const spot = held(core.spotShadow);
		const cube = held(core.cubeShadow);
		assert sun.kind === ShadowKind.Sun && spot.kind === ShadowKind.Spot && cube.kind === ShadowKind.Cube;
		assert sun.size === 512 && spot.size === 256 && cube.size === 128;
		assert sun.samplingKind === ShadowSamplingKind.Pcf && spot.samplingKind === ShadowSamplingKind.Pcf &&
			cube.samplingKind === ShadowSamplingKind.Pcf;
		assert refs[0].scene.lights[1].shadows && refs[0].scene.lights[2].shadows && !refs[0].scene.lights[0].shadows;
		let block: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		assert collectLights(refs[0].scene, block).ok, "one caster of each kind is what Void accepts";
	} finally { dispose(); resetErrorHalt(); }
	assert refs[0].renderer.closed;
}

test "shadowNormalBias and shadowRadius reach the map of each kind and follow their props" {
	const refs: Scene3DHandle[] = [];
	const [bias, setBias] = createSignal<float32>(1.5);
	const [radius, setRadius] = createSignal<float32>(2.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		<DirectionalLight castShadow={true} shadowNormalBias={bias()} shadowRadius={radius()} />
		<SpotLight angle={QUARTER} penumbra={0.5} distance={8.0} castShadow={true} shadowNormalBias={bias()} shadowRadius={radius()} />
		<PointLight castShadow={true} shadowNormalBias={bias()} shadowRadius={radius()} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const core = refs[0].renderer.core;
		const maps: DirShadowMap[] = [held(core.shadow), held(core.spotShadow), held(core.cubeShadow)];
		for (const map of maps) { assert approx(map.normalBias, 1.5) && approx(map.pcfScale, 2.0); }
		setBias(0.25); setRadius(4.0); flush();
		for (const map of maps) { assert approx(map.normalBias, 0.25) && approx(map.pcfScale, 4.0); }
	} finally { dispose(); resetErrorHalt(); }
}

test "an unset spot shadow takes Void's defaults of bias, normal bias and pcfScale" {
	const refs: Scene3DHandle[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		<SpotLight angle={QUARTER} penumbra={0.5} distance={8.0} castShadow={true} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const spot = held(refs[0].renderer.core.spotShadow);
		assert approx(spot.bias, 0.01) && approx(spot.normalBias, 0.0) && approx(spot.pcfScale, 1.0) && approx(spot.opacity, 1.0);
	} finally { dispose(); resetErrorHalt(); }
}

test "a second caster of one kind is refused by name, and another kind is not" {
	assert refused((): NeonNode => element(<Scene3D>
		<SpotLight angle={QUARTER} penumbra={0.5} distance={8.0} castShadow={true} />
		<SpotLight angle={QUARTER} penumbra={0.5} distance={8.0} castShadow={true} />
	</Scene3D>)).includes("Light: only one spot Light casts shadows in a Scene3D");
	assert refused((): NeonNode => element(<Scene3D>
		<PointLight castShadow={true} />
		<PointLight castShadow={true} />
	</Scene3D>)).includes("Light: only one point, rectangle or capsule Light casts shadows in a Scene3D");
	assert refused((): NeonNode => element(<Scene3D>
		<DirectionalLight castShadow={true} />
		<Light kind={LightKind.Directional} castShadow={true} />
	</Scene3D>)).includes("Light: only one directional Light casts shadows in a Scene3D");
}

test "a point light's castShadow is fixed at mount, as Void has no light-shadows binder" {
	const refs: Scene3DHandle[] = [];
	const [first, setFirst] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		<PointLight castShadow={first()} />
		<PointLight castShadow={!first()} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const core = refs[0].renderer.core;
		assert held(core.cubeShadow).kind === ShadowKind.Cube;
		let message = "";
		try { setFirst(false); flush(); }
		catch (error) { message = error.toString(); }
		finally { resetErrorHalt(); }
		assert message.includes("Light: castShadow is fixed at mount on a Point light");
	} finally { dispose(); resetErrorHalt(); }
}

test "shadow props are refused on a light without castShadow and out of range, for the new kinds too" {
	assert refused((): NeonNode => element(<Scene3D><PointLight shadowRadius={2.0} /></Scene3D>))
		.includes("need castShadow");
	assert refused((): NeonNode => element(<Scene3D><SpotLight angle={QUARTER} penumbra={0.5} distance={8.0} shadowNormalBias={1.0} /></Scene3D>))
		.includes("need castShadow");
	assert refused((): NeonNode => element(<Scene3D><PointLight castShadow={true} shadowRadius={-1.0} /></Scene3D>))
		.includes("Light: invalid shadow settings");
	assert refused((): NeonNode => element(<Scene3D>
		<SpotLight angle={QUARTER} penumbra={0.5} distance={8.0} castShadow={true} shadowMapSize={0} />
	</Scene3D>)).includes("Light: invalid shadow settings");
}
