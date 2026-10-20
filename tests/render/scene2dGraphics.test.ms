import { accessor, createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Graphics } from "../../src/components/scene2d";
import { GraphicsOp } from "../../src/render/graphics";
import { NodeRef, GraphicsMesh, Scene2D as VoidScene2D, isLive, graphics, dispose } from "../../../void/src/void2d/node";
import { Vec2, vec2, rgba } from "../../../void/src/void2d/types";
import {
	fillTriangle, fillConvex, fillCircle, fillEllipse, fillPie, fillRing,
	fillRoundedRect, strokeLine, strokePoly, strokeRect, quadBezier, cubicBezier,
} from "../../../void/src/void2d/graphics";

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
		flush();
		assert geometry(nodes[0]).mesh.length === 0;
	} finally { dispose(); }
	const stopped = reads;
	setOperations(initial);
	flush();
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
		{Show({ when: accessor(() => shown()), children: element(
			<Graphics operations={operations}
				ref={(node: NodeRef): void => { nodes.push(node); }} />
		) })}
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		assert nodes.length === 1 && geometry(nodes[0]).mesh.length === 48;
		setShown(false);
		flush();
		assert !nodes[0].isLive();
		setShown(true);
		flush();
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

test "Graphics solid shapes and curve helpers match direct Void geometry after each edit" {
	const nodes: NodeRef[] = [];
	const color = rgba(0.2, 0.4, 0.6, 0.8);
	const a = vec2(0.0, 0.0);
	const b = vec2(10.0, 0.0);
	const c = vec2(0.0, 10.0);
	const points: Vec2[] = [a, b, c];
	const curve = quadBezier(a, c, b, 8);
	const cubic = cubicBezier(a, c, vec2(8.0, 9.0), b, 7);
	const operations: GraphicsOp[] = [
		{ kind: "fillTriangle", a: a, b: b, c: c, color: color },
		{ kind: "fillConvex", points: points, color: color },
		{ kind: "strokeLine", a: a, b: b, width: 3.0, color: color },
		{ kind: "strokePoly", points: curve, width: 2.0, closed: false, color: color },
		{ kind: "strokePoly", points: cubic, width: 4.0, closed: true, color: color },
		{ kind: "strokeRect", x: 1.0, y: 2.0, w: 8.0, h: 6.0,
			width: 2.0, color: color },
		{ kind: "fillCircle", cx: 2.0, cy: 3.0, r: 5.0, color: color },
		{ kind: "fillEllipse", cx: 2.0, cy: 3.0, rx: 5.0, ry: 7.0, color: color },
		{ kind: "fillRoundedRect", x: 1.0, y: 2.0, w: 8.0, h: 6.0,
			radius: 9.0, color: color },
		{ kind: "fillPie", cx: 2.0, cy: 3.0, r: 5.0,
			angleStart: 0.5, angleLength: 2.0, color: color },
		{ kind: "fillRing", cx: 2.0, cy: 3.0, outerR: 6.0, innerR: 3.0,
			angleStart: 0.5, angleLength: 2.0, color: color },
	];
	const controls: ((node: NodeRef) => NodeRef)[] = [
		(node: NodeRef): NodeRef => node.fillTriangle(a, b, c, color),
		(node: NodeRef): NodeRef => node.fillConvex(points, color),
		(node: NodeRef): NodeRef => node.strokeLine(a, b, 3.0, color),
		(node: NodeRef): NodeRef => node.strokePoly(curve, 2.0, color, false),
		(node: NodeRef): NodeRef => node.strokePoly(cubic, 4.0, color, true),
		(node: NodeRef): NodeRef => node.strokeRect(1.0, 2.0, 8.0, 6.0, 2.0, color),
		(node: NodeRef): NodeRef => node.fillCircle(2.0, 3.0, 5.0, color),
		(node: NodeRef): NodeRef => node.fillEllipse(2.0, 3.0, 5.0, 7.0, color),
		(node: NodeRef): NodeRef => node.fillRoundedRect(1.0, 2.0, 8.0, 6.0, 9.0, color),
		(node: NodeRef): NodeRef => node.fillPie(2.0, 3.0, 5.0, 0.5, 2.0, color),
		(node: NodeRef): NodeRef => node.fillRing(2.0, 3.0, 6.0, 3.0, 0.5, 2.0, color),
	];
	const [value, setValue] = createSignal<GraphicsOp[]>([]);
	const root = mockNode("root");
	const cleanup = render(element(<Void><Scene2D>
		<Graphics operations={value()} ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const id = nodes[0].id;
		for (let i: int32 = 0; i < operations.length; i++) {
			setValue([operations[i]]);
			flush();
			const control = nodes[0].scene.graphics();
			try {
				controls[i](control);
				const actual = geometry(nodes[0]);
				const expected = geometry(control);
				assert actual.mesh.length === expected.mesh.length && actual.mesh.length > 0;
				for (let j: int32 = 0; j < actual.mesh.length; j++) {
					assert actual.mesh[j] === expected.mesh[j];
				}
				assert nodes[0].id === id && nodes.length === 1;
			} finally { control.dispose(); }
		}
	} finally { cleanup(); }
}
