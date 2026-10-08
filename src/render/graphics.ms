import { NodeRef, clear } from "../../../void/src/void2d/node";
import { Vec2, Color } from "../../../void/src/void2d/types";
import { fillRect, fillPolygon } from "../../../void/src/void2d/graphics";

export struct FillRectOp {
	kind: "fillRect";
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	color: Color;
}

export struct FillPolygonOp {
	kind: "fillPolygon";
	points: Vec2[];
	color: Color;
}

export type GraphicsOp = FillRectOp | FillPolygonOp;

export function replayGraphics(node: NodeRef, operations: Span<GraphicsOp>): void {
	node.clear();
	for (const op of operations) {
		match (op.kind) {
			"fillRect" => { node.fillRect(op.x, op.y, op.w, op.h, op.color); }
			"fillPolygon" => { node.fillPolygon(op.points, op.color); }
		}
	}
}
