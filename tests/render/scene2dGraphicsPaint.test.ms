import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Graphics } from "../../src/components/scene2d";
import { GraphicsOp } from "../../src/render/graphics";
import { NodeRef, graphics, dispose } from "../../../void/src/void2d/node";
import { vec2, rgba } from "../../../void/src/void2d/types";
import { GradientSpace } from "../../../void/src/void2d/gradient";
import {
	fillGradientPolygon, fillGradientPolygonOklab, fillGradientPolygonStops,
	fillGradientRect, fillGradientRectOklab, fillGradientRectStops,
	fillRadialGradient, fillRadialGradientOklab, fillRadialGradientStops,
	fillSlashRect, fillCheckerRect,
} from "../../../void/src/void2d/graphics";

test "Graphics gradients and patterns preserve direct Void vertices and ordered shader records" {
	const points = [vec2(1.0, 2.0), vec2(10.0, 2.0), vec2(5.0, 9.0)];
	const a = rgba(1.0, 0.0, 0.0, 0.3);
	const m = rgba(0.0, 1.0, 0.0, 0.6);
	const b = rgba(0.0, 0.0, 1.0, 0.9);
	const operations: GraphicsOp[] = [
		{ kind: "fillGradientPolygon", points: points, c0: a, c1: b, angle: 0.4 },
		{ kind: "fillGradientPolygonOklab", points: points, c0: a, c1: b, angle: 0.7 },
		{ kind: "fillGradientPolygonStops", points: points, c0: a, cMiddle: m, c1: b,
			middle: 0.2, angle: 0.5, space: GradientSpace.Oklab },
		{ kind: "fillGradientRect", x: 2.0, y: 3.0, w: 10.0, h: 8.0,
			c0: a, c1: b, angle: 0.4 },
		{ kind: "fillGradientRectOklab", x: 2.0, y: 3.0, w: 10.0, h: 8.0,
			c0: a, c1: b, angle: 0.7 },
		{ kind: "fillGradientRectStops", x: 2.0, y: 3.0, w: 10.0, h: 8.0,
			c0: a, cMiddle: m, c1: b, middle: 0.8, angle: 0.5, space: GradientSpace.Srgb },
		{ kind: "fillRadialGradient", cx: 9.0, cy: 8.0, r: 6.0, cInner: a, cOuter: b },
		{ kind: "fillRadialGradientOklab", cx: 9.0, cy: 8.0, r: 6.0, cInner: a, cOuter: b },
		{ kind: "fillRadialGradientStops", cx: 9.0, cy: 8.0, r: 6.0,
			c0: a, cMiddle: m, c1: b, middle: 0.3, space: GradientSpace.Oklab },
		{ kind: "fillSlashRect", x: 2.0, y: 3.0, w: 10.0, h: 8.0,
			background: a, stripe: b, spacing: 7.0, width: 2.0 },
		{ kind: "fillCheckerRect", x: 2.0, y: 3.0, w: 10.0, h: 8.0, a: a, b: b, cell: 4.0 },
	];
	const controls: ((node: NodeRef) => NodeRef)[] = [
		(node: NodeRef): NodeRef => node.fillGradientPolygon(points, a, b, 0.4),
		(node: NodeRef): NodeRef => node.fillGradientPolygonOklab(points, a, b, 0.7),
		(node: NodeRef): NodeRef => node.fillGradientPolygonStops(points, a, m, b, 0.2, 0.5, GradientSpace.Oklab),
		(node: NodeRef): NodeRef => node.fillGradientRect(2.0, 3.0, 10.0, 8.0, a, b, 0.4),
		(node: NodeRef): NodeRef => node.fillGradientRectOklab(2.0, 3.0, 10.0, 8.0, a, b, 0.7),
		(node: NodeRef): NodeRef => node.fillGradientRectStops(2.0, 3.0, 10.0, 8.0, a, m, b, 0.8, 0.5, GradientSpace.Srgb),
		(node: NodeRef): NodeRef => node.fillRadialGradient(9.0, 8.0, 6.0, a, b),
		(node: NodeRef): NodeRef => node.fillRadialGradientOklab(9.0, 8.0, 6.0, a, b),
		(node: NodeRef): NodeRef => node.fillRadialGradientStops(9.0, 8.0, 6.0, a, m, b, 0.3, GradientSpace.Oklab),
		(node: NodeRef): NodeRef => node.fillSlashRect(2.0, 3.0, 10.0, 8.0, a, b, 7.0, 2.0),
		(node: NodeRef): NodeRef => node.fillCheckerRect(2.0, 3.0, 10.0, 8.0, a, b, 4.0),
	];
	const nodes: NodeRef[] = [];
	const [value, setValue] = createSignal<GraphicsOp[]>([]);
	const cleanup = render(element(<Void><Scene2D>
		<Graphics operations={value()} ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
	const control = nodes[0].scene.graphics();
	try {
		const id = nodes[0].id;
		const prefix: GraphicsOp[] = [];
		for (let i: int32 = 0; i < operations.length; i++) {
			prefix.push(operations[i]);
			const snapshot: GraphicsOp[] = [];
			for (const op of prefix) { snapshot.push(op); }
			setValue(snapshot);
			controls[i](control);
			const actual = nodes[0].scene.meshes[nodes[0].scene.payloads[id.index]];
			const expected = control.scene.meshes[control.scene.payloads[control.id.index]];
			assert nodes.length === 1 && nodes[0].id === id;
			assert actual.mesh.length === expected.mesh.length && actual.mesh.length > 0;
			assert actual.records.length === expected.records.length && actual.records.length > 0;
			for (let j: int32 = 0; j < actual.mesh.length; j++) {
				assert actual.mesh[j] === expected.mesh[j];
			}
			for (let j: int32 = 0; j < actual.records.length; j++) {
				assert actual.records[j] === expected.records[j];
			}
		}
		setValue([]);
		const empty = nodes[0].scene.meshes[nodes[0].scene.payloads[id.index]];
		assert empty.mesh.length === 0 && empty.records.length === 0;
	} finally { control.dispose(); cleanup(); }
}
