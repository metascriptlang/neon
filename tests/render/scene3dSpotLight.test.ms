import { accessor, createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Light, SpotLight, DirectionalLight, PointLight } from "../../src/components/scene3d";
import { NodeId3D, LightKind, LightShape, LightError, collectLights } from "../../../void/src/void3d/scene";
import { LIGHT_UNIFORM_LENGTH } from "../../../void/src/void3d/gpu3d";
import { TextureId, NO_TEXTURE } from "../../../void/src/void3d/texture";
import { vec3 } from "../../../void/src/math/math3d";
import { approx } from "../../../void/src/test/helpers";

const QUARTER: float32 = 0.7853981634;
const SIXTH: float32 = 0.5235987756;
const COOKIE_A: TextureId = { store: 0, index: 3, generation: 1 };
const COOKIE_B: TextureId = { store: 0, index: 4, generation: 1 };

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

function shapeOf(handle: Scene3DHandle, node: NodeId3D): LightShape {
	return handle.scene.lights[handle.scene.nodes[node.index].payload].shape;
}

test "a SpotLight reaches Void as a full cone and an inner half angle that collectLights accepts" {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		<SpotLight angle={QUARTER} penumbra={0.5} distance={8.0}
			ref={(node: NodeId3D): void => { nodes.push(node); }} />
		<SpotLight angle={SIXTH} penumbra={1.0} distance={5.0}
			ref={(node: NodeId3D): void => { nodes.push(node); }} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const first = shapeOf(refs[0], nodes[0]);
		assert approx(first.angle, QUARTER * 2.0) && approx(first.falloff, QUARTER * 0.5);
		const second = shapeOf(refs[0], nodes[1]);
		assert approx(second.angle, SIXTH * 2.0) && approx(second.falloff, 0.0);
		assert refs[0].scene.lights[0].kind === LightKind.Spot && approx(refs[0].scene.lights[0].radius, 8.0);
		let block: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		assert collectLights(refs[0].scene, block).ok, "a spot with a shape is not BadLightShape";
	} finally { dispose(); resetErrorHalt(); }
}

test "a Light of kind Spot takes a shape of its own, and a kind that reads none refuses one" {
	const shape: LightShape = {
		angle: 1.0, verticalAngle: 0.0, falloff: 0.2, width: 0.0, height: 0.0, length: 0.0, capsuleRadius: 0.0,
	};
	const refs: Scene3DHandle[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		<Light kind={LightKind.Spot} shape={shape} radius={6.0} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		let block: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		assert collectLights(refs[0].scene, block).ok;
	} finally { dispose(); resetErrorHalt(); }
	assert refused((): NeonNode => element(<Scene3D><Light kind={LightKind.Spot} /></Scene3D>))
		.includes("Light: kind Spot needs shape");
	assert refused((): NeonNode => element(<Scene3D><Light kind={LightKind.Capsule} /></Scene3D>))
		.includes("Light: kind Capsule needs shape");
	assert refused((): NeonNode => element(<Scene3D><Light kind={LightKind.Point} shape={shape} /></Scene3D>))
		.includes("Light: shape needs a Spot, Rectangle or Capsule kind, not Point");
	assert refused((): NeonNode => element(<Scene3D><Light kind={LightKind.Directional} shape={shape} /></Scene3D>))
		.includes("Light: shape needs a Spot, Rectangle or Capsule kind, not Directional");
}

test "a SpotLight cone Void refuses is named at mount, penumbra 0 and a half angle of PI/2 alike" {
	assert refused((): NeonNode => element(<Scene3D><SpotLight angle={QUARTER} penumbra={0.0} distance={5.0} /></Scene3D>))
		.includes("Light: kind Spot refuses its shape: SingularAngle");
	assert refused((): NeonNode => element(<Scene3D><SpotLight angle={1.5707963268} penumbra={0.5} distance={5.0} /></Scene3D>))
		.includes("Light: kind Spot refuses its shape: BadAngle");
	assert refused((): NeonNode => element(<Scene3D><SpotLight angle={QUARTER} penumbra={0.5} distance={0.0} /></Scene3D>))
		.includes("Light: kind Spot refuses its shape: BadRange");
}

test "a SpotLight shape is fixed at mount and its distance follows the prop" {
	const refs: Scene3DHandle[] = [];
	const [angle, setAngle] = createSignal<float32>(QUARTER);
	const [distance, setDistance] = createSignal<float32>(5.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		<SpotLight angle={angle()} penumbra={0.5} distance={distance()} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		setDistance(9.0); flush();
		assert approx(refs[0].scene.lights[0].radius, 9.0);
		let message = "";
		try { setAngle(SIXTH); flush(); }
		catch (error) { message = error.toString(); }
		finally { resetErrorHalt(); }
		assert message.includes("Light: shape is fixed at mount; Void has no light-shape binder");
	} finally { dispose(); resetErrorHalt(); }
}

test "a SpotLight map is the light's cookie, follows its prop, and is refused on another kind" {
	const refs: Scene3DHandle[] = [];
	const [map, setMap] = createSignal<TextureId>(COOKIE_A);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		<SpotLight angle={QUARTER} penumbra={0.5} distance={8.0} map={map()} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		assert refs[0].scene.lights[0].cookie === COOKIE_A;
		setMap(COOKIE_B); flush();
		assert refs[0].scene.lights[0].cookie === COOKIE_B;
		setMap(NO_TEXTURE); flush();
		assert !refs[0].scene.lights[0].cookie.isTexture();
	} finally { dispose(); resetErrorHalt(); }
	assert refused((): NeonNode => element(<Scene3D><Light kind={LightKind.Point} cookie={COOKIE_A} /></Scene3D>))
		.includes("Light: cookie needs a Spot light, not Point");
	assert refused((): NeonNode => element(<Scene3D><DirectionalLight /><Light kind={LightKind.Directional} cookie={COOKIE_A} /></Scene3D>))
		.includes("Light: cookie needs a Spot light, not Directional");
}

test "two seen spots with a map are refused per frame, and the second takes the map once the first lets it go" {
	const [first, setFirst] = createSignal<TextureId>(COOKIE_A);
	const refs: Scene3DHandle[] = [];
	const [second, setSecond] = createSignal<TextureId>(COOKIE_B);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		<SpotLight angle={QUARTER} penumbra={0.5} distance={8.0} map={first()} />
		<SpotLight angle={QUARTER} penumbra={0.5} distance={8.0} map={second()} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		let both: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const twice = collectLights(refs[0].scene, both);
		assert !twice.ok && twice.error === LightError.TooManyCookieSpots;
		setFirst(NO_TEXTURE); flush();
		assert refs[0].scene.lights[1].cookie === COOKIE_B && !refs[0].scene.lights[0].cookie.isTexture();
		let block: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		assert collectLights(refs[0].scene, block).ok;
	} finally { dispose(); resetErrorHalt(); }
}

test "two seen Directional lights are refused per frame, and removing one lets the frame through beside a PointLight" {
	const refs: Scene3DHandle[] = [];
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		{Show({ when: accessor(() => shown()), children: element(<DirectionalLight />) })}
		<Light kind={LightKind.Directional} />
		<PointLight />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		let block: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const twice = collectLights(refs[0].scene, block);
		assert !twice.ok && twice.error === LightError.TooManyDirectionalLights;
		setShown(false); flush();
		assert collectLights(refs[0].scene, block).ok;
		setShown(true); flush();
		const again = collectLights(refs[0].scene, block);
		assert !again.ok && again.error === LightError.TooManyDirectionalLights;
	} finally { dispose(); resetErrorHalt(); }
}
