import { accessor, createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { createRoot } from "../../src/core/owner";
import { resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { useContext } from "../../src/render/context";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Group, Camera3D, Lod } from "../../src/components/scene3d";
import { SceneState, sceneScope, runBeforeRefresh } from "../../src/components/scene3d/core";
import { NodeId3D } from "../../../void/src/void3d/scene";
import { Vec3, vec3 } from "../../../void/src/math/math3d";

function Capture(states: SceneState[]): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = useContext(sceneScope);
		if (scope !== null) { states.push(scope.state); }
	};
}

function shownLevels(handle: Scene3DHandle, levels: NodeId3D[]): string {
	let out = "";
	for (const level of levels) {
		out += handle.scene.nodes[level.index].isVisible() ? "1" : "0";
	}
	return out;
}

test "Lod selects its level by Void MeshLod projected size, like Heaps Mesh LOD" {
	const refs: Scene3DHandle[] = [];
	const states: SceneState[] = [];
	const levels: NodeId3D[] = [];
	const [eye, setEye] = createSignal<Vec3>(vec3(0.0, 0.0, -3.0));
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
			{Capture(states)}
			<Camera3D active={true} position={eye()} />
			<Lod radius={1.0} thresholds={[0.5, 0.2]} cullingRatio={0.05} position={vec3(0.0, 0.0, -5.0)}>
				<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
				<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
				<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
			</Lod>
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	const handle = refs[0];
	const state = states[0];
	const at = (z: float32, expected: string, why: string): void => {
		setEye(vec3(0.0, 0.0, z));
		flush();
		runBeforeRefresh(state, 320, 240);
		assert shownLevels(handle, levels) === expected, why + ": " + shownLevels(handle, levels);
	};
	at(-3.0, "100", "2 away covers 0.87 of the screen, above 0.5");
	at(0.0, "010", "5 away covers 0.35, between 0.5 and 0.2");
	at(10.0, "001", "15 away covers 0.12, below 0.2");
	at(40.0, "000", "45 away covers 0.04, below the culling ratio");
	at(-3.0, "100", "coming back shows level 0");
	dispose();
	assert state.beforeRefresh.length === 0, "unmount drops the level selection";
}

test "Lod world scale grows the projected size and forcedLevel overrides the selection" {
	const refs: Scene3DHandle[] = [];
	const states: SceneState[] = [];
	const levels: NodeId3D[] = [];
	const [scale, setScale] = createSignal<Vec3>(vec3(1.0, 1.0, 1.0));
	const [forced, setForced] = createSignal<int32 | null>(null);
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
			{Capture(states)}
			<Camera3D active={true} position={vec3(0.0, 0.0, 0.0)} />
			<Lod radius={1.0} thresholds={[0.5]} forcedLevel={forced()} position={vec3(0.0, 0.0, -5.0)} scale={scale()}>
				<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
				<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
			</Lod>
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	const handle = refs[0];
	runBeforeRefresh(states[0], 320, 240);
	assert shownLevels(handle, levels) === "01", "radius 1 at 5 covers 0.35: " + shownLevels(handle, levels);
	setScale(vec3(1.0, 2.0, 1.0));
	flush();
	runBeforeRefresh(states[0], 320, 240);
	assert shownLevels(handle, levels) === "10", "the largest world axis scales the radius: " + shownLevels(handle, levels);
	setForced(1);
	flush();
	runBeforeRefresh(states[0], 320, 240);
	assert shownLevels(handle, levels) === "01", "forcedLevel wins: " + shownLevels(handle, levels);
	setForced(2);
	flush();
	runBeforeRefresh(states[0], 320, 240);
	assert shownLevels(handle, levels) === "00", "a forced level past the last one culls: " + shownLevels(handle, levels);
}

test "Lod hides children beyond its thresholds and follows changed thresholds" {
	const refs: Scene3DHandle[] = [];
	const states: SceneState[] = [];
	const levels: NodeId3D[] = [];
	const [thresholds, setThresholds] = createSignal<float32[]>([0.5]);
	const [shown, setShown] = createSignal(true);
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
			{Capture(states)}
			<Camera3D active={true} position={vec3(0.0, 0.0, 5.0)} />
			{Show({ when: accessor(() => shown()), children: element(
				<Lod radius={1.0} thresholds={thresholds()}>
					<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
					<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
					<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
				</Lod>
			) })}
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	const handle = refs[0];
	runBeforeRefresh(states[0], 320, 240);
	assert shownLevels(handle, levels) === "010", "a level without a threshold is never selected: " + shownLevels(handle, levels);
	setThresholds([0.3, 0.1]);
	flush();
	runBeforeRefresh(states[0], 320, 240);
	assert shownLevels(handle, levels) === "100", "new thresholds apply on the next frame: " + shownLevels(handle, levels);
	setShown(false);
	flush();
	assert states[0].beforeRefresh.length === 0 && !handle.scene.isLive(levels[0]), "a parked Lod leaves no hook and no nodes";
}

function refusal(app: () => NeonNode): string {
	let message = "";
	createRoot((dispose: () => void): void => {
		try {
			app()(mockHost(), mockNode("root") as unknown as HostNode, null);
		} catch (error) { message = error.toString(); } finally { dispose(); resetErrorHalt(); }
	});
	return message;
}

test "Lod refuses a MeshLod config Void refuses and a radius that is not a size" {
	const ascending = refusal((): NeonNode => element(<Void><Scene3D><Lod radius={1.0} thresholds={[0.2, 0.5]} /></Scene3D></Void>));
	assert ascending.includes("Lod") && ascending.includes("descending"), "names the rule: " + ascending;
	const culling = refusal((): NeonNode => element(<Void><Scene3D><Lod radius={1.0} thresholds={[0.5]} cullingRatio={-1.0} /></Scene3D></Void>));
	assert culling.includes("Lod") && culling.includes("cullingRatio"), "names the rule: " + culling;
	const radius = refusal((): NeonNode => element(<Void><Scene3D><Lod radius={-1.0} thresholds={[0.5]} /></Scene3D></Void>));
	assert radius.includes("Lod") && radius.includes("radius"), "names the rule: " + radius;
}
