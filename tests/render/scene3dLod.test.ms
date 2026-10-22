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

test "Lod shows the level whose distance the camera has passed, like three LOD.update" {
	const refs: Scene3DHandle[] = [];
	const states: SceneState[] = [];
	const levels: NodeId3D[] = [];
	const [eye, setEye] = createSignal<Vec3>(vec3(0.0, 0.0, 4.0));
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
			{Capture(states)}
			<Camera3D active={true} position={eye()} />
			<Lod distances={[0.0, 10.0, 20.0]} position={vec3(0.0, 0.0, -5.0)}>
				<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
				<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
				<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
			</Lod>
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	const handle = refs[0];
	const state = states[0];
	runBeforeRefresh(state, 320, 240);
	assert shownLevels(handle, levels) === "100", "9 away shows level 0: " + shownLevels(handle, levels);
	setEye(vec3(0.0, 0.0, 10.0));
	flush();
	runBeforeRefresh(state, 320, 240);
	assert shownLevels(handle, levels) === "010", "15 away shows level 1: " + shownLevels(handle, levels);
	setEye(vec3(0.0, 0.0, 40.0));
	flush();
	runBeforeRefresh(state, 320, 240);
	assert shownLevels(handle, levels) === "001", "45 away shows level 2: " + shownLevels(handle, levels);
	setEye(vec3(0.0, 0.0, 4.0));
	flush();
	runBeforeRefresh(state, 320, 240);
	assert shownLevels(handle, levels) === "100", "coming back shows level 0: " + shownLevels(handle, levels);
	dispose();
	assert state.beforeRefresh.length === 0, "unmount drops the level selection";
}

test "Lod hysteresis keeps the shown level until the camera passes the band" {
	const refs: Scene3DHandle[] = [];
	const states: SceneState[] = [];
	const levels: NodeId3D[] = [];
	const [eye, setEye] = createSignal<Vec3>(vec3(0.0, 0.0, 12.0));
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
			{Capture(states)}
			<Camera3D active={true} position={eye()} />
			<Lod distances={[0.0, 10.0]} hysteresis={0.2}>
				<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
				<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
			</Lod>
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	const handle = refs[0];
	runBeforeRefresh(states[0], 320, 240);
	assert shownLevels(handle, levels) === "01";
	setEye(vec3(0.0, 0.0, 9.0));
	flush();
	runBeforeRefresh(states[0], 320, 240);
	assert shownLevels(handle, levels) === "01", "inside the 20% band keeps level 1: " + shownLevels(handle, levels);
	setEye(vec3(0.0, 0.0, 7.0));
	flush();
	runBeforeRefresh(states[0], 320, 240);
	assert shownLevels(handle, levels) === "10", "past the band shows level 0: " + shownLevels(handle, levels);
}

test "Lod hides children beyond its distances and follows a changed distances list" {
	const refs: Scene3DHandle[] = [];
	const states: SceneState[] = [];
	const levels: NodeId3D[] = [];
	const [distances, setDistances] = createSignal<float32[]>([0.0, 10.0]);
	const [shown, setShown] = createSignal(true);
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
			{Capture(states)}
			<Camera3D active={true} position={vec3(0.0, 0.0, 15.0)} />
			{Show({ when: accessor(() => shown()), children: element(
				<Lod distances={distances()}>
					<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
					<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
					<Group ref={(value: NodeId3D): void => { levels.push(value); }} />
				</Lod>
			) })}
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	const handle = refs[0];
	runBeforeRefresh(states[0], 320, 240);
	assert shownLevels(handle, levels) === "010", "a child without a distance is hidden: " + shownLevels(handle, levels);
	setDistances([0.0, 20.0, 30.0]);
	flush();
	runBeforeRefresh(states[0], 320, 240);
	assert shownLevels(handle, levels) === "100", "new distances apply on the next frame: " + shownLevels(handle, levels);
	setShown(false);
	flush();
	assert states[0].beforeRefresh.length === 0 && !handle.scene.isLive(levels[0]), "a parked Lod leaves no hook and no nodes";
}

test "Lod refuses distances that are not finite, non-negative and ascending" {
	let message = "";
	createRoot((dispose: () => void): void => {
		try {
			element(<Void><Scene3D><Lod distances={[0.0, 20.0, 10.0]} /></Scene3D></Void>)(mockHost(), mockNode("root") as unknown as HostNode, null);
		} catch (error) { message = error.toString(); } finally { dispose(); resetErrorHalt(); }
	});
	assert message.includes("Lod") && message.includes("ascending"), "names the rule: " + message;
}
