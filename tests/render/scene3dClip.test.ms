import { accessor, createSignal, Accessor } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show, Errored } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { NeonNode } from "../../src/render/node";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Gltf, Clip, ClipHandle } from "../../src/components/scene3d";
import { useManualFrames, setFrameDriver, framePending } from "../../src/animation/frame";
import { vec3 } from "../../../void/src/math/math3d";
import { Transform3D } from "../../../void/src/void3d/scene";
import { GltfData, GltfTransform, GltfAnimation } from "../../../void/src/void3d/gltf";
import { GltfMaterialSetup } from "../../../void/src/void3d/gltfScene";
import { GltfCurve, GltfCurvePath, GltfCurveMode, forValues } from "../../../void/src/void3d/gltfCurve";
import { RenderState } from "../../../void/src/gpu/state";

function slideCurve(path: GltfCurvePath, to: float32): GltfCurve {
	const values: Vec<float32> = path === GltfCurvePath.Translation
		? [0.0, 0.0, 0.0, to, 0.0, 0.0]
		: [1.0, 1.0, 1.0, to, to, to];
	const curve = GltfCurve.forValues(path, GltfCurveMode.Linear, [0.0, 1.0], values);
	if (!curve.ok) { throw new Error("fixture curve"); }
	return curve.value;
}

function rigged(): GltfData {
	return riggedAt(0.0);
}

function riggedAt(hipX: float32): GltfData {
	const identity = Transform3D.identity();
	const rest: GltfTransform = { position: identity.position, rotation: identity.rotation, scale: identity.scale };
	const walk: GltfAnimation = { name: "Walk", tracks: [
		{ sourceNode: 1, curve: slideCurve(GltfCurvePath.Translation, 10.0) },
	] };
	const run: GltfAnimation = { name: "Run", tracks: [
		{ sourceNode: 1, curve: slideCurve(GltfCurvePath.Translation, -10.0) },
		{ sourceNode: 2, curve: slideCurve(GltfCurvePath.Scale, 3.0) },
	] };
	return {
		meshes: [], meshMaterials: [], materials: [], textures: [], sceneRoots: [0],
		nodes: [
			{ name: "hip", mesh: -1, local: { ...rest, position: vec3(hipX, 0.0, 0.0) }, children: [1, 2] },
			{ name: "arm", mesh: -1, local: rest, children: [] },
			{ name: "leg", mesh: -1, local: rest, children: [] },
		],
		animations: [walk, run],
	};
}

function setup(): GltfMaterialSetup {
	return { pass: RenderState.defaults(), block: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0] };
}

function localOf(handle: Scene3DHandle, name: string): Transform3D {
	const found = handle.scene.findByName(handle.scene.rootId(), name);
	if (!found.ok) { throw new Error("no node " + name); }
	return handle.scene.nodes[found.value.index].local;
}

function armX(handle: Scene3DHandle): float32 {
	return localOf(handle, "arm").position.x;
}

function legScale(handle: Scene3DHandle): float32 {
	return localOf(handle, "leg").scale.x;
}

function near(a: float32, b: float32): boolean {
	return Math.abs(a - b) < 1e-3;
}

test "a Clip plays its glTF animation on the Gltf nodes and loops on the area clock" {
	const frames = useManualFrames();
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { handle = value; }}>
		<Gltf data={rigged()} setup={setup()}><Clip name={"Walk"} /></Gltf>
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		assert near(armX(handle), 0.0);
		frames.advance(500);
		assert near(armX(handle), 5.0), "half the clip: " + armX(handle).toString();
		frames.advance(750);
		assert near(armX(handle), 2.5), "loops: " + armX(handle).toString();
		assert framePending();
	} finally { dispose(); setFrameDriver(null); }
	assert !framePending();
}

test "Clip playing speed loop and time props steer the clip and a paused or finished scene sleeps" {
	const frames = useManualFrames();
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const [playing, setPlaying] = createSignal(true);
	const [speed, setSpeed] = createSignal<float64>(1.0);
	const [loop, setLoop] = createSignal(true);
	const [time, setTime] = createSignal<float64>(0.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { handle = value; }}>
		<Gltf data={rigged()} setup={setup()}>
			<Clip name={"Walk"} playing={playing()} speed={speed()} loop={loop()} time={time()} />
		</Gltf>
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		frames.advance(250);
		assert near(armX(handle), 2.5);
		setPlaying(false); flush();
		assert !framePending(), "a paused clip sleeps";
		frames.advance(1000);
		assert near(armX(handle), 2.5), "and holds its pose";
		setPlaying(true); setSpeed(2.0); flush();
		frames.advance(125);
		assert near(armX(handle), 5.0), "speed doubles: " + armX(handle).toString();
		setTime(0.8); flush();
		assert near(armX(handle), 8.0), "time seeks";
		setLoop(false); setSpeed(1.0); flush();
		frames.advance(500);
		assert near(armX(handle), 10.0) && !framePending(), "a one-shot holds its end and sleeps";
		setTime(0.0); flush();
		assert near(armX(handle), 0.0) && framePending(), "seeking back wakes it";
	} finally { dispose(); setFrameDriver(null); }
}

test "Clips under one Gltf blend by weight, fade, and leave untouched nodes at rest" {
	const frames = useManualFrames();
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const [runWeight, setRunWeight] = createSignal<float64>(1.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { handle = value; }}>
		<Gltf data={rigged()} setup={setup()}>
			<Clip name={"Walk"} />
			<Clip name={"Run"} weight={runWeight()} fadeMs={100.0} />
		</Gltf>
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		frames.advance(500);
		assert near(armX(handle), 0.0), "walk +5 and run -5 at equal weight: " + armX(handle).toString();
		assert near(legScale(handle), 1.5), "run alone scales the leg, at half weight: " + legScale(handle).toString();
		setRunWeight(0.0); flush();
		frames.advance(50);
		assert near(armX(handle), 5.5 / 3.0), "run at half weight: " + armX(handle).toString();
		assert near(legScale(handle), 1.0 + 1.1 / 3.0), "leg: " + legScale(handle).toString();
		frames.advance(100);
		assert near(armX(handle), 6.5), "run faded out, walk alone: " + armX(handle).toString();
		assert near(legScale(handle), 1.0), "the leg returns to rest: " + legScale(handle).toString();
	} finally { dispose(); setFrameDriver(null); }
}

test "a ClipHandle crossfades, stops and plays on the same state as the props" {
	const frames = useManualFrames();
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const clips: ClipHandle[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { handle = value; }}>
		<Gltf data={rigged()} setup={setup()}>
			<Clip name={"Walk"} ref={(clip: ClipHandle): void => { clips.push(clip); }} />
			<Clip name={"Run"} weight={0.0} ref={(clip: ClipHandle): void => { clips.push(clip); }} />
		</Gltf>
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		frames.advance(500);
		assert near(armX(handle), 5.0);
		clips[0].crossfade(clips[1], 200.0);
		frames.advance(100);
		assert near(legScale(handle), 1.0 + 2.0 * 0.1 * 0.5), "run fades in halfway: " + legScale(handle).toString();
		frames.advance(100);
		assert near(armX(handle), -2.0), "run alone after the fade: " + armX(handle).toString();
		clips[1].pause();
		assert !framePending(), "walk faded out and run paused: nothing to animate";
		clips[1].stop();
		flush();
		assert near(armX(handle), 0.0) && near(legScale(handle), 1.0), "stopped clips leave the rest pose";
		assert !framePending();
		clips[0].setWeight(1.0);
		clips[0].play();
		assert framePending();
		frames.advance(100);
		assert armX(handle) > 0.0;
	} finally { dispose(); setFrameDriver(null); }
}

test "a Clip naming no animation fails through Errored and unmounting restores the rest pose" {
	const frames = useManualFrames();
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const [shown, setShown] = createSignal(true);
	const errors: string[] = [];
	const root = mockNode("root");
	const failing = render(Errored({
		children: element(<Void><Scene3D><Gltf data={rigged()} setup={setup()}><Clip name={"Fly"} /></Gltf></Scene3D></Void>),
		fallback: (error: Accessor<Error>, reset: () => void): NeonNode => {
			errors.push(error().message);
			return element(<Void />);
		},
	}), mockHost(), root as unknown as HostNode);
	failing();
	assert errors.length === 1 && errors[0] === "Clip: the Gltf has no animation named \"Fly\"", errors.join("|");
	const second = mockNode("second");
	const dispose = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { handle = value; }}>
		<Gltf data={rigged()} setup={setup()}>
			{Show({ when: accessor(() => shown()), children: element(<Clip name={"Run"} />) })}
		</Gltf>
	</Scene3D></Void>), mockHost(), second as unknown as HostNode);
	try {
		frames.advance(500);
		assert near(legScale(handle), 2.0);
		setShown(false); flush();
		assert near(legScale(handle), 1.0) && near(armX(handle), 0.0), "rest after the last clip leaves";
		assert !framePending();
	} finally { dispose(); setFrameDriver(null); }
}

test "Clips follow a Gltf whose data is replaced and keep blending on the new nodes" {
	const frames = useManualFrames();
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const [hip, setHip] = createSignal<float32>(0.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { handle = value; }}>
		<Gltf data={riggedAt(hip())} setup={setup()}>
			<Clip name={"Walk"} />
			<Clip name={"Run"} weight={0.5} />
		</Gltf>
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		frames.advance(500);
		setHip(7.0); flush();
		assert near(localOf(handle, "hip").position.x, 7.0), "the new graph is mounted";
		frames.advance(250);
		assert near(armX(handle), (2.5 * 1.0 - 2.5 * 0.5) / 1.5), "both clips restart on the new nodes: " + armX(handle).toString();
		assert near(legScale(handle), (1.0 + 1.5 * 0.5) / 1.5), "leg: " + legScale(handle).toString();
	} finally { dispose(); setFrameDriver(null); }
}
