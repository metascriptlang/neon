import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Graphics } from "../../src/components/scene2d";
import { GraphicsOp } from "../../src/render/graphics";
import { NodeRef, GraphicsMesh, Scene2D as VoidScene2D, isLive } from "../../../void/src/void2d/node";
import { Vec2, vec2, rgba } from "../../../void/src/void2d/types";

function geometry(node: NodeRef): GraphicsMesh {
	return node.scene.meshes[node.scene.payloads[node.id.index]];
}

test "Graphics replay replaces geometry in order and snapshots caller polygon points" {
	const nodes: NodeRef[] = [];
	const scenes: VoidScene2D[] = [];
	const points: Vec2[] = [vec2(1.0, 2.0), vec2(5.0, 2.0), vec2(1.0, 8.0)];
	const initial: GraphicsOp[] = [
		{ kind: "fillRect", x: 10.0, y: 20.0, w: 4.0, h: 6.0,
			color: rgba(1.0, 0.0, 0.0, 1.0) },
		{ kind: "fillPolygon", points: points, color: rgba(0.0, 1.0, 0.0, 1.0) },
	];
	const [operations, setOperations] = createSignal<GraphicsOp[]>(initial);
	let reads: int32 = 0;
	const read = (): GraphicsOp[] => { reads += 1; return operations(); };
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D
		ref={(scene: VoidScene2D): void => { scenes.push(scene); }}>
		<Graphics operations={read()} ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const id = nodes[0].id;
		assert geometry(nodes[0]).mesh.length === 72;
		assert geometry(nodes[0]).mesh[0] === 10.0;
		assert geometry(nodes[0]).mesh[48] === 1.0;
		points[0] = vec2(99.0, 99.0);
		assert geometry(nodes[0]).mesh[48] === 1.0;
		setOperations([{
			kind: "fillRect", x: 30.0, y: 40.0, w: 2.0, h: 3.0,
			color: rgba(0.0, 0.0, 1.0, 1.0),
		}]);
		assert geometry(nodes[0]).mesh.length === 48;
		assert geometry(nodes[0]).mesh[0] === 30.0;
		assert nodes.length === 1 && nodes[0].id === id;
		setOperations([]);
		assert geometry(nodes[0]).mesh.length === 0;
	} finally { dispose(); }
	const stopped = reads;
	setOperations(initial);
	assert reads === stopped && scenes[0].closed && !nodes[0].isLive();
}

test "Graphics remount owns fresh geometry and rejects missing Scene2D scope" {
	const nodes: NodeRef[] = [];
	const [shown, setShown] = createSignal(true);
	const operations: GraphicsOp[] = [{
		kind: "fillRect", x: 1.0, y: 2.0, w: 3.0, h: 4.0,
		color: rgba(1.0, 1.0, 1.0, 1.0),
	}];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		{Show({ when: () => shown(), children: element(
			<Graphics operations={operations}
				ref={(node: NodeRef): void => { nodes.push(node); }} />
		) })}
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		assert nodes.length === 1 && geometry(nodes[0]).mesh.length === 48;
		setShown(false);
		assert !nodes[0].isLive();
		setShown(true);
		assert nodes.length === 2 && geometry(nodes[1]).mesh.length === 48;
		assert !nodes[0].isLive() && nodes[1].isLive();
	} finally { dispose(); }
	assert !nodes[1].isLive();
	let message = "";
	try {
		const cleanup = render(element(<Graphics operations={operations} />),
			mockHost(), mockNode("root") as unknown as HostNode);
		cleanup();
	} catch (error) { message = error.message; }
	assert message === "Graphics: mount inside Scene2D within Void";
}
