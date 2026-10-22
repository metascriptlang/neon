// A 3D scene inside a <Void> area: a spinning box, a shadow on the ground, a label, a glTF model,
// and a 2D HUD over it whose button changes the scene.
//   msc run examples/scene3d.ms                (run from the neon checkout: font and model paths are relative)
//   msc run examples/scene3d.ms -- --frames=60  exits 0 after 60 frames

import { argv, exit } from "std/process";
import { readFile } from "std/fs";
import { createSignal } from "../src/core/signal";
import { element } from "../src/macros/ui/element";
import { Show } from "../src/macros/ui/flow";
import { NeonNode } from "../src/render/node";
import { Void, View, Text, Pressable } from "../src/components/primitives";
import { Scene3D, Camera3D, Light, Mesh, Text3D, Gltf, gltfData, useFrame } from "../src/components/scene3d";
import { runWindow, desktopOptions } from "../src/platform/ion/window";
import { vec3, eulerQuat } from "../../void/src/math/math3d";
import { LightKind } from "../../void/src/void3d/scene";
import { MeshData, addBox, addPlane } from "../../void/src/void3d/meshData";
import { GltfData, loadGlbDetailed } from "../../void/src/void3d/gltf";

function box(): MeshData {
	let data = MeshData.empty();
	const made = addBox(data, { base: vec3(0.0, -0.5, 0.0), size: vec3(1.0, 1.0, 1.0), yaw: 0.0, tilt: 0.0,
		color: { red: 0.95, green: 0.55, blue: 0.2, alpha: 1.0 } });
	if (!made.ok) { throw new Error("box: " + made.error.toString()); }
	return data;
}

function ground(): MeshData {
	let data = MeshData.empty();
	const made = addPlane(data, 4.0, { red: 0.35, green: 0.4, blue: 0.5, alpha: 1.0 });
	if (!made.ok) { throw new Error("ground: " + made.error.toString()); }
	return data;
}

const MODEL = "../void/tests/fixtures/gltf/texturedScene.glb";

function model(): GltfData {
	const file = readFile(MODEL);
	if (!file.ok) { throw new Error("model: " + file.error.toString()); }
	const bytes: Vec<uint8> = [...file.value.asBytes()];
	return gltfData(loadGlbDetailed(bytes, MODEL));
}

function framesToRun(): int32 {
	for (const arg of argv) {
		if (arg.startsWith("--frames=")) { return parseInt(arg.slice(9)) as int32; }
	}
	return 0;
}

function App(): NeonNode {
	const [angle, setAngle] = createSignal<float32>(0.0);
	const [spinning, setSpinning] = createSignal(true);
	const [showModel, setShowModel] = createSignal(true);
	const cube = box();
	const floor = ground();
	const scene = model();
	const exitAfter = framesToRun();
	let frames = 0;
	useFrame((dt: number): void => {
		if (spinning()) { setAngle(angle() + (dt as float32)); }
		frames += 1;
		if (exitAfter > 0 && frames >= exitAfter) { exit(0); }
	});
	return element(
		<Void style={{ backgroundColor: "#11111b" }}>
			<Scene3D ambient={vec3(0.25, 0.25, 0.3)}>
				<Camera3D active={true} position={vec3(0.0, 3.0, 7.0)} pitch={0.35} />
				<Light kind={LightKind.Directional} rotation={eulerQuat(1.0, 2.6, 0.0)} castShadow={true} />
				<Mesh geometry={floor} receiveShadow={true} />
				<Mesh geometry={cube} position={vec3(-1.2, 1.0, 0.0)} rotation={eulerQuat(0.0, angle(), 0.0)}
					castShadow={true} receiveShadow={true} />
				<Text3D text={spinning() ? "spinning" : "paused"} position={vec3(-1.2, 2.2, 0.0)} billboard={true} />
				<Show when={showModel()}>
					<Gltf data={scene} position={vec3(1.5, 0.0, 0.0)} />
				</Show>
			</Scene3D>
			<View style={{ position: "absolute", top: 16, left: 16, flexDirection: "row", gap: 8 }}>
				<Pressable style={{ width: 120, height: 32, padding: 8, backgroundColor: "#89b4fa" }} onPress={(): void => { setSpinning(!spinning()); }}>
					<Text style={{ color: "#11111b" }}>{spinning() ? "Pause" : "Spin"}</Text>
				</Pressable>
				<Pressable style={{ width: 120, height: 32, padding: 8, backgroundColor: "#a6e3a1" }} onPress={(): void => { setShowModel(!showModel()); }}>
					<Text style={{ color: "#11111b" }}>{showModel() ? "Hide model" : "Show model"}</Text>
				</Pressable>
			</View>
		</Void>
	);
}

exit(runWindow({ ...desktopOptions("Neon Scene3D", 800, 500), font: "../void/assets/font.ttf" }, App));
