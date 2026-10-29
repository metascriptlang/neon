import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { Host, HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { NeonNode } from "../../src/render/hostTypes";
import { Void } from "../../src/components/primitives";
import { Scene3DHandle, SceneState, sceneScope, runBeforeRefresh } from "../../src/components/scene3d/core";
import { Scene3D } from "../../src/components/scene3d/scene";
import { Line, LineProps } from "../../src/components/scene3d/line";
import { useContext } from "../../src/render/context";
import { NodeId3D } from "../../../void/src/void3d/scene";
import { DrawContext, MaterialId, MeshId } from "../../../void/src/void3d/draw";
import { Program, LINE_WIDTH, LINE_LENGTH_SCALE, LINE_PIXEL_SIZE, LINE_NEAR, LINE_FAR, LINE_COLOR } from "../../../void/src/void3d/gpu3d";
import { vertexCount } from "../../../void/src/void3d/meshData";
import { Color, rgba } from "../../../void/src/void2d/types";
import { Vec3, vec3 } from "../../../void/src/math/math3d";

function block(context: DrawContext, material: MaterialId, at: int32): float32 {
	return context.uniforms.values[context.materials[material.index].uniforms.offset + at];
}

function meshOf(handle: Scene3DHandle, node: NodeId3D): MeshId {
	return handle.scene.meshes[handle.scene.nodes[node.index].payload].mesh;
}

function materialOf(handle: Scene3DHandle, node: NodeId3D): MaterialId {
	return handle.scene.meshes[handle.scene.nodes[node.index].payload].material;
}

function quads(handle: Scene3DHandle, node: NodeId3D): int32 {
	return handle.context.meshData[meshOf(handle, node).index].vertexCount() / 4;
}

function ahead(count: int32): Vec3[] {
	const points: Vec3[] = [];
	for (let i = 0; i < count; i++) { points.push(vec3(i as float32, 0.0, -3.0)); }
	return points;
}

function mountedWith(props: LineProps): [Scene3DHandle, SceneState, NodeId3D[], () => void] {
	const refs: Scene3DHandle[] = [];
	const states: SceneState[] = [];
	const nodes: NodeId3D[] = [];
	const painted: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = useContext(sceneScope);
		if (scope !== null) { states.push(scope.state); }
		Line({ ...props, ref: (node: NodeId3D): void => { nodes.push(node); } })(host, parent, before);
	};
	const dispose = render(element(<Void>
		<Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>{painted}</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	return [refs[0], states[0], nodes, dispose];
}

function refusalWith(props: LineProps): string {
	let message = "";
	try {
		const [handle, state, nodes, dispose] = mountedWith(props);
		dispose();
	} catch (error) { message = error.message; }
	finally { resetErrorHalt(); }
	return message;
}

test "Line draws one quad per segment of the polyline with Void's line program, and the frame writes its block" {
	const [handle, state, nodes, dispose] = mountedWith({
		points: accessor((): Vec3[] => ahead(4)),
		color: accessor((): Color => rgba(0.5, 0.25, 0.75, 1.0)),
		lineWidth: accessor((): float32 => 4.0),
	});
	try {
		assert quads(handle, nodes[0]) === 3;
		const material = materialOf(handle, nodes[0]);
		assert handle.context.materials[material.index].program.program === Program.Line;
		runBeforeRefresh(state, 320, 240);
		assert block(handle.context, material, LINE_WIDTH) === 4.0 && block(handle.context, material, LINE_LENGTH_SCALE) === 1.0;
		assert block(handle.context, material, LINE_PIXEL_SIZE) === 2.0 / 320.0;
		assert block(handle.context, material, LINE_PIXEL_SIZE + 1) === 2.0 / 240.0;
		assert block(handle.context, material, LINE_NEAR) === 0.1 && block(handle.context, material, LINE_FAR) === 1000.0;
		assert block(handle.context, material, LINE_COLOR) === 0.5 && block(handle.context, material, LINE_COLOR + 1) === 0.25;
		assert block(handle.context, material, LINE_COLOR + 2) === 0.75 && block(handle.context, material, LINE_COLOR + 3) === 1.0;
	} finally { dispose(); resetErrorHalt(); }
}

test "Line segments reads the points as separate pairs" {
	const [handle, state, nodes, dispose] = mountedWith({
		points: accessor((): Vec3[] => ahead(4)), segments: accessor((): boolean => true),
	});
	try {
		assert quads(handle, nodes[0]) === 2, "two pairs, not three joined segments";
		const material = materialOf(handle, nodes[0]);
		runBeforeRefresh(state, 320, 240);
		assert block(handle.context, material, LINE_WIDTH) === 1.0, "lineWidth defaults to drei's 1";
		assert block(handle.context, material, LINE_COLOR) === 1.0, "color defaults to white";
	} finally { dispose(); resetErrorHalt(); }
}

test "Line points, width, color and segments each rebind through their own binder" {
	const [points, setPoints] = createSignal<Vec3[]>(ahead(2));
	const [width, setWidth] = createSignal<float32>(2.0);
	const [color, setColor] = createSignal<Color>(rgba(1.0, 0.0, 0.0, 1.0));
	const [pairs, setPairs] = createSignal<boolean>(false);
	const [handle, state, nodes, dispose] = mountedWith({
		points: accessor((): Vec3[] => points()), lineWidth: accessor((): float32 => width()),
		color: accessor((): Color => color()), segments: accessor((): boolean => pairs()),
	});
	try {
		const material = materialOf(handle, nodes[0]);
		const first = meshOf(handle, nodes[0]);
		assert quads(handle, nodes[0]) === 1;
		setPoints(ahead(5)); flush();
		assert meshOf(handle, nodes[0]) !== first && quads(handle, nodes[0]) === 4, "new points make a new mesh";
		assert !handle.context.hasMesh(first), "the old mesh is released";
		assert materialOf(handle, nodes[0]) === material, "the material stays";
		setWidth(8.0); setColor(rgba(0.0, 1.0, 0.0, 1.0)); flush();
		runBeforeRefresh(state, 320, 240);
		assert block(handle.context, material, LINE_WIDTH) === 8.0 && block(handle.context, material, LINE_COLOR + 1) === 1.0;
		setPoints(ahead(6)); flush();
		runBeforeRefresh(state, 320, 240);
		assert block(handle.context, material, LINE_WIDTH) === 8.0, "a new mesh keeps the width";
		setPairs(true); flush();
		assert quads(handle, nodes[0]) === 3, "segments pairs six points into three quads";
		assert nodes.length === 1;
	} finally { dispose(); resetErrorHalt(); }
}

test "Line unmount removes the node and releases the material" {
	const [on, setOn] = createSignal(true);
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	const materials: MaterialId[] = [];
	const painted: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		Line({
			points: accessor((): Vec3[] => ahead(2)),
			ref: (node: NodeId3D): void => { nodes.push(node); materials.push(materialOf(refs[0], node)); },
		})(host, parent, before);
	};
	const dispose = render(element(<Void>
		<Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
			{Show({ when: accessor(() => on()), children: painted })}
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	try {
		assert refs[0].scene.isLive(nodes[0]) && refs[0].context.hasMaterial(materials[0]);
		setOn(false); flush();
		assert !refs[0].scene.isLive(nodes[0]) && !refs[0].context.hasMaterial(materials[0]);
	} finally { dispose(); resetErrorHalt(); }
}

test "Line refuses outside a Scene3D, bad points, bad width, and what Void cannot draw" {
	let message = "";
	try {
		const lost: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			Line({ points: accessor((): Vec3[] => ahead(2)) })(host, parent, before);
		};
		const cleanup = render(element(<Void>{lost}</Void>), mockHost(), mockNode("root") as unknown as HostNode);
		cleanup();
	} catch (error) { message = error.message; }
	finally { resetErrorHalt(); }
	assert message === "Line: mount inside Scene3D within Void", message;

	const one = refusalWith({ points: accessor((): Vec3[] => ahead(1)) });
	assert one.includes("Line: points needs at least 2 points, got 1"), one;
	const none = refusalWith({ points: accessor((): Vec3[] => ahead(0)) });
	assert none.includes("Line: points needs at least 2 points, got 0"), none;
	const odd = refusalWith({ points: accessor((): Vec3[] => ahead(3)), segments: accessor((): boolean => true) });
	assert odd.includes("Line: segments reads points in pairs, got 3 points"), odd;
	const bad = ahead(3);
	bad[1] = vec3(Number.NaN as float32, 0.0, 0.0);
	const nan = refusalWith({ points: accessor((): Vec3[] => bad) });
	assert nan.includes("Line: points[1] must be finite"), nan;
	const far = ahead(3);
	far[2] = vec3(0.0, Number.POSITIVE_INFINITY as float32, 0.0);
	const infinite = refusalWith({ points: accessor((): Vec3[] => far) });
	assert infinite.includes("Line: points[2] must be finite"), infinite;
	const zero = refusalWith({ points: accessor((): Vec3[] => ahead(2)), lineWidth: accessor((): float32 => 0.0) });
	assert zero.includes("Line: lineWidth must be a finite number of pixels above 0"), zero;
	const negative = refusalWith({ points: accessor((): Vec3[] => ahead(2)), lineWidth: accessor((): float32 => -1.0) });
	assert negative.includes("Line: lineWidth must be"), negative;
	const dim = refusalWith({ points: accessor((): Vec3[] => ahead(2)), color: accessor((): Color => rgba(1.0, 1.0, 1.0, 0.5)) });
	assert dim.includes("Line: color alpha must be 1"), dim;
	const vertex = refusalWith({
		points: accessor((): Vec3[] => ahead(2)), vertexColors: accessor((): Color[] => [rgba(1.0, 0.0, 0.0, 1.0)]),
	});
	assert vertex.includes("Line: vertexColors has no counterpart"), vertex;
	const dashed = refusalWith({ points: accessor((): Vec3[] => ahead(2)), dashed: accessor((): boolean => true) });
	assert dashed.includes("Line: dashed has no counterpart"), dashed;
}
