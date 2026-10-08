import { NodeRef, clear } from "../../../void/src/void2d/node";
import { Vec2, Color } from "../../../void/src/void2d/types";
import {
	fillRect, fillPolygon, fillTriangle, fillConvex, fillCircle, fillEllipse,
	fillPie, fillRing, fillRoundedRect, strokeLine, strokePoly, strokeRect,
} from "../../../void/src/void2d/graphics";

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

export struct FillConvexOp {
	kind: "fillConvex";
	points: Vec2[];
	color: Color;
}

export struct FillTriangleOp {
	kind: "fillTriangle";
	a: Vec2;
	b: Vec2;
	c: Vec2;
	color: Color;
}

export struct StrokeLineOp {
	kind: "strokeLine";
	a: Vec2;
	b: Vec2;
	width: float32;
	color: Color;
}

export struct StrokePolyOp {
	kind: "strokePoly";
	points: Vec2[];
	width: float32;
	closed: boolean;
	color: Color;
}

export struct StrokeRectOp {
	kind: "strokeRect";
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	width: float32;
	color: Color;
}

export struct FillCircleOp {
	kind: "fillCircle";
	cx: float32;
	cy: float32;
	r: float32;
	color: Color;
}

export struct FillEllipseOp {
	kind: "fillEllipse";
	cx: float32;
	cy: float32;
	rx: float32;
	ry: float32;
	color: Color;
}

export struct FillRoundedRectOp {
	kind: "fillRoundedRect";
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	radius: float32;
	color: Color;
}

export struct FillPieOp {
	kind: "fillPie";
	cx: float32;
	cy: float32;
	r: float32;
	angleStart: float32;
	angleLength: float32;
	color: Color;
}

export struct FillRingOp {
	kind: "fillRing";
	cx: float32;
	cy: float32;
	outerR: float32;
	innerR: float32;
	angleStart: float32;
	angleLength: float32;
	color: Color;
}

export type GraphicsOp = FillRectOp | FillPolygonOp | FillConvexOp | FillTriangleOp |
	StrokeLineOp | StrokePolyOp | StrokeRectOp | FillCircleOp | FillEllipseOp |
	FillRoundedRectOp | FillPieOp | FillRingOp;

export function replayGraphics(node: NodeRef, operations: Span<GraphicsOp>): void {
	node.clear();
	for (const op of operations) {
		match (op.kind) {
			"fillRect" => { node.fillRect(op.x, op.y, op.w, op.h, op.color); }
			"fillPolygon" => { node.fillPolygon(op.points, op.color); }
			"fillConvex" => { node.fillConvex(op.points, op.color); }
			"fillTriangle" => { node.fillTriangle(op.a, op.b, op.c, op.color); }
			"strokeLine" => { node.strokeLine(op.a, op.b, op.width, op.color); }
			"strokePoly" => { node.strokePoly(op.points, op.width, op.color, op.closed); }
			"strokeRect" => { node.strokeRect(op.x, op.y, op.w, op.h, op.width, op.color); }
			"fillCircle" => { node.fillCircle(op.cx, op.cy, op.r, op.color); }
			"fillEllipse" => { node.fillEllipse(op.cx, op.cy, op.rx, op.ry, op.color); }
			"fillRoundedRect" => {
				node.fillRoundedRect(op.x, op.y, op.w, op.h, op.radius, op.color);
			}
			"fillPie" => {
				node.fillPie(op.cx, op.cy, op.r, op.angleStart, op.angleLength, op.color);
			}
			"fillRing" => {
				node.fillRing(op.cx, op.cy, op.outerR, op.innerR,
					op.angleStart, op.angleLength, op.color);
			}
		}
	}
}
