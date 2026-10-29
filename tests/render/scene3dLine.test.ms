import { Accessor, accessor } from "../../src/core/signal";
import { resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { Host, HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { NeonNode } from "../../src/render/hostTypes";
import { Void } from "../../src/components/primitives";
import { Scene3DHandle, SceneState, sceneScope } from "../../src/components/scene3d/core";
import { Scene3D } from "../../src/components/scene3d/scene";
import { Line, LineProps } from "../../src/components/scene3d/line";
import { useContext } from "../../src/render/context";
import { NodeId3D } from "../../../void/src/void3d/scene";
import { Color, rgba } from "../../../void/src/void2d/types";
import { Vec3, vec3 } from "../../../void/src/math/math3d";

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
