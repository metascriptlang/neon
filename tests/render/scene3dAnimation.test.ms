import { accessor, createSignal, Accessor } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show, Errored } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { NeonNode } from "../../src/render/node";
import { Void } from "../../src/components/primitives";
import {
	Scene3D, Scene3DHandle, Group, Mesh, ObjectAnimation, MeshFrameAnimation,
} from "../../src/components/scene3d";
import { useManualFrames, setFrameDriver, framePending } from "../../src/animation/frame";
import { vec3 } from "../../../void/src/math/math3d";
import { Transform3D } from "../../../void/src/void3d/scene";
import {
	AnimationClock, ObjectAnimation as VoidObjectAnimation, Interpolation,
	forFrames, forClock, addTrack,
} from "../../../void/src/void3d/animation";
import { DrawContext, MeshId, releaseMesh } from "../../../void/src/void3d/draw";
import { added, litShape } from "../../../void/src/test/drawHelpers";

function slide(x: float32): Transform3D {
	return Transform3D.fromTranslation(vec3(x, 0.0, 0.0));
}

function sliding(target: string): VoidObjectAnimation {
	const clock = AnimationClock.forFrames(3, 10.0, Interpolation.Linear);
	if (!clock.ok) { throw new Error("clock"); }
	let animation = VoidObjectAnimation.forClock(clock.value);
	const track = addTrack(animation, target, [slide(0.0), slide(10.0), slide(20.0)]);
	if (!track.ok) { throw new Error("track"); }
	return animation;
}

function xOf(handle: Scene3DHandle, name: string): float32 {
	const found = handle.scene.findByName(handle.scene.rootId(), name);
	if (!found.ok) { return -1000.0; }
	return handle.scene.nodes[found.value.index].local.position.x;
}

function near(a: float32, b: float32): boolean {
	return Math.abs(a - b) < 1e-3;
}

test "ObjectAnimation poses its tracks at mount and advances on the area clock" {
	const frames = useManualFrames();
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { handle = value; }}>
		<Group name={"rig"} position={vec3(5.0, 0.0, 0.0)}>
			<ObjectAnimation animation={sliding("arm")} />
			<Group name={"arm"} />
		</Group>
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		assert near(xOf(handle, "arm"), 0.0), "frame zero before the first tick";
		assert near(xOf(handle, "rig"), 5.0), "the parent keeps its own transform";
		frames.advance(50);
		assert near(xOf(handle, "arm"), 5.0), "half a key in 50 ms at 10 fps: " + xOf(handle, "arm").toString();
		frames.advance(100);
		assert near(xOf(handle, "arm"), 15.0);
		frames.advance(150);
		assert near(xOf(handle, "arm"), 0.0), "loops by default: " + xOf(handle, "arm").toString();
		assert framePending();
	} finally { dispose(); setFrameDriver(null); }
	assert !framePending(), "unmount stops the clock";
}

test "ObjectAnimation paused speed looping and frame props steer one clock and finishing idles" {
	const frames = useManualFrames();
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const [paused, setPaused] = createSignal(false);
	const [speed, setSpeed] = createSignal<float64>(1.0);
	const [looping, setLooping] = createSignal(true);
	const [frame, setFrame] = createSignal<float64>(0.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { handle = value; }}>
		<Group>
			<Group name={"arm"} />
			<ObjectAnimation animation={sliding("arm")} paused={paused()} speed={speed()}
				looping={looping()} frame={frame()} />
		</Group>
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		frames.advance(50);
		assert near(xOf(handle, "arm"), 5.0);
		setPaused(true); flush();
		assert !framePending(), "paused sleeps";
		frames.advance(1000);
		setPaused(false); flush();
		frames.advance(50);
		assert near(xOf(handle, "arm"), 10.0), "resumes from where it paused: " + xOf(handle, "arm").toString();
		setSpeed(0.0); flush();
		assert !framePending(), "speed zero sleeps";
		setSpeed(2.0); flush();
		frames.advance(25);
		assert near(xOf(handle, "arm"), 15.0);
		setFrame(1.0); flush();
		assert near(xOf(handle, "arm"), 10.0), "frame seeks";
		setLooping(false); setSpeed(1.0); flush();
		frames.advance(100);
		assert near(xOf(handle, "arm"), 20.0);
		frames.advance(100);
		assert near(xOf(handle, "arm"), 20.0) && !framePending(), "a one-shot holds its last key and sleeps";
		frames.advance(1000);
		assert !framePending();
		setFrame(0.0); flush();
		assert framePending() && near(xOf(handle, "arm"), 0.0), "seeking back wakes it";
	} finally { dispose(); setFrameDriver(null); }
}

test "ObjectAnimation refuses a missing target through Errored and recovers on reset" {
	const frames = useManualFrames();
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const [name, setName] = createSignal("leg");
	const errors: string[] = [];
	const resets: (() => void)[] = [];
	const root = mockNode("root");
	const dispose = render(Errored({
		children: element(<Void><Scene3D ref={(value: Scene3DHandle): void => { handle = value; }}>
			<Group><Group name={name()} /><ObjectAnimation animation={sliding("arm")} /></Group>
		</Scene3D></Void>),
		fallback: (error: Accessor<Error>, reset: () => void): NeonNode => {
			errors.push(error().message); resets.push(reset);
			return element(<Void />);
		},
	}), mockHost(), root as unknown as HostNode);
	try {
		assert errors.length === 1 && errors[0] === "ObjectAnimation: bindTracks failed: TargetNotFound", errors.join("|");
		assert !framePending(), "an unbound animation asks for no frame";
		setName("arm"); flush();
		resets[0](); flush();
		assert framePending(), "reset binds and plays";
		frames.advance(50);
		assert near(xOf(handle, "arm"), 5.0);
	} finally { dispose(); setFrameDriver(null); }
}

test "a healthy ObjectAnimation keeps playing beside one whose target was removed" {
	const frames = useManualFrames();
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const [shown, setShown] = createSignal(true);
	const errors: string[] = [];
	const root = mockNode("root");
	const broken = render(Errored({
		children: element(<Void><Scene3D ref={(value: Scene3DHandle): void => { handle = value; }}>
			<Group>
				{Show({ when: accessor(() => shown()), children: element(<Group name={"arm"} />) })}
				<ObjectAnimation animation={sliding("arm")} />
			</Group>
		</Scene3D></Void>),
		fallback: (error: Accessor<Error>, reset: () => void): NeonNode => {
			errors.push(error().message);
			return element(<Void />);
		},
	}), mockHost(), root as unknown as HostNode);
	let healthy: Scene3DHandle = null as unknown as Scene3DHandle;
	const healthyRoot = mockNode("healthy");
	const stopHealthy = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { healthy = value; }}>
		<Group><Group name={"arm"} /><ObjectAnimation animation={sliding("arm")} /></Group>
	</Scene3D></Void>), mockHost(), healthyRoot as unknown as HostNode);
	try {
		frames.advance(50);
		setShown(false); flush();
		frames.advance(50);
		assert errors.length === 1 && errors[0] === "ObjectAnimation: syncPose failed: StaleTarget", errors.join("|");
		assert near(xOf(healthy, "arm"), 10.0);
		frames.advance(50);
		assert near(xOf(healthy, "arm"), 15.0), "the healthy clock keeps ticking";
	} finally { broken(); stopHealthy(); setFrameDriver(null); }
}

function releaseAll(context: DrawContext, meshes: Vec<MeshId>): void {
	for (const mesh of meshes) {
		const released = releaseMesh(context, mesh);
		if (!released.ok) { throw new Error("fixture releaseMesh: " + released.error.toString()); }
	}
}

test "MeshFrameAnimation steps the named mesh through borrowed frames and unpins them on unmount" {
	const frames = useManualFrames();
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	let baked: Vec<MeshId> = [];
	const [shown, setShown] = createSignal(true);
	const [looping, setLooping] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => {
		handle = value;
		for (let i = 0; i < 3; i++) { baked.push(added(value.context, litShape())); }
	}}>
		<Group>
			<Mesh name={"body"} mesh={baked[0]} />
			{Show({ when: accessor(() => shown()), children: element(
				<MeshFrameAnimation target={"body"} meshes={baked} fps={10.0} looping={looping()} />
			) })}
		</Group>
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const body = handle.scene.findByName(handle.scene.rootId(), "body");
		assert body.ok;
		if (!body.ok) { return; }
		const row = handle.scene.nodes[body.value.index].payload;
		assert handle.scene.meshes[row].mesh === baked[0];
		assert handle.context.meshPins[baked[1].index] === 1, "the animation pins every frame";
		frames.advance(100);
		assert handle.scene.meshes[row].mesh === baked[1], "the next baked frame";
		frames.advance(100);
		assert handle.scene.meshes[row].mesh === baked[2];
		setLooping(false); flush();
		frames.advance(100);
		assert handle.scene.meshes[row].mesh === baked[2] && !framePending(), "a one-shot holds its last frame";
		setShown(false); flush();
		assert handle.context.meshPins[baked[1].index] === 0, "unmount unpins the frames";
		assert handle.scene.meshes[row].mesh === baked[2], "the node keeps the frame it shows";
	} finally { releaseAll(handle.context, baked); dispose(); setFrameDriver(null); }
}

test "MeshFrameAnimation refuses a target that is not a mesh" {
	const errors: string[] = [];
	let baked: Vec<MeshId> = [];
	let context: DrawContext = null as unknown as DrawContext;
	const root = mockNode("root");
	const dispose = render(Errored({
		children: element(<Void><Scene3D ref={(value: Scene3DHandle): void => {
			context = value.context;
			baked.push(added(value.context, litShape()));
		}}><Group>
			<Group name={"body"} />
			<MeshFrameAnimation target={"body"} meshes={baked} fps={10.0} />
		</Group></Scene3D></Void>),
		fallback: (error: Accessor<Error>, reset: () => void): NeonNode => {
			errors.push(error().message);
			return element(<Void />);
		},
	}), mockHost(), root as unknown as HostNode);
	releaseAll(context, baked);
	dispose();
	assert errors.length === 1 && errors[0] === "MeshFrameAnimation: bindMeshFrames failed: NotAMeshNode", errors.join("|");
}
