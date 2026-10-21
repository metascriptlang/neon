import { NodeRef, clear } from "../../../void/src/void2d/node";
import { Vec2, Color, Tile, TextureSource, WHITE_SOURCE, sameAs } from "../../../void/src/void2d/types";
import { GradientSpace } from "../../../void/src/void2d/gradient";
import {
	fillRect, fillPolygon, fillTriangle, fillConvex, fillCircle, fillEllipse,
	fillPie, fillRing, fillRoundedRect, strokeLine, strokePoly, strokeRect,
	fillGradientPolygon, fillGradientPolygonOklab, fillGradientPolygonStops,
	fillGradientRect, fillGradientRectOklab, fillGradientRectStops,
	fillRadialGradient, fillRadialGradientOklab, fillRadialGradientStops,
	fillSlashRect, fillCheckerRect, fillTexRect, fillTexPolygon,
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

export struct FillGradientPolygonOp {
	kind: "fillGradientPolygon";
	points: Vec2[];
	c0: Color;
	c1: Color;
	angle: float32;
}

export struct FillGradientPolygonOklabOp {
	kind: "fillGradientPolygonOklab";
	points: Vec2[];
	c0: Color;
	c1: Color;
	angle: float32;
}

export struct FillGradientPolygonStopsOp {
	kind: "fillGradientPolygonStops";
	points: Vec2[];
	c0: Color;
	cMiddle: Color;
	c1: Color;
	middle: float32;
	angle: float32;
	space: GradientSpace;
}

export struct FillGradientRectOp {
	kind: "fillGradientRect";
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	c0: Color;
	c1: Color;
	angle: float32;
}

export struct FillGradientRectOklabOp {
	kind: "fillGradientRectOklab";
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	c0: Color;
	c1: Color;
	angle: float32;
}

export struct FillGradientRectStopsOp {
	kind: "fillGradientRectStops";
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	c0: Color;
	cMiddle: Color;
	c1: Color;
	middle: float32;
	angle: float32;
	space: GradientSpace;
}

export struct FillRadialGradientOp {
	kind: "fillRadialGradient";
	cx: float32;
	cy: float32;
	r: float32;
	cInner: Color;
	cOuter: Color;
}

export struct FillRadialGradientOklabOp {
	kind: "fillRadialGradientOklab";
	cx: float32;
	cy: float32;
	r: float32;
	cInner: Color;
	cOuter: Color;
}

export struct FillRadialGradientStopsOp {
	kind: "fillRadialGradientStops";
	cx: float32;
	cy: float32;
	r: float32;
	c0: Color;
	cMiddle: Color;
	c1: Color;
	middle: float32;
	space: GradientSpace;
}

export struct FillSlashRectOp {
	kind: "fillSlashRect";
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	background: Color;
	stripe: Color;
	spacing: float32;
	width: float32;
}

export struct FillCheckerRectOp {
	kind: "fillCheckerRect";
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	a: Color;
	b: Color;
	cell: float32;
}

export struct FillTexRectOp {
	kind: "fillTexRect";
	tile: Tile;
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	color: Color;
}

export struct FillTexPolygonOp {
	kind: "fillTexPolygon";
	tile: Tile;
	points: Vec2[];
	originX: float32;
	originY: float32;
	tileW: float32;
	tileH: float32;
	color: Color;
}

export type GraphicsOp = FillRectOp | FillPolygonOp | FillConvexOp | FillTriangleOp |
	StrokeLineOp | StrokePolyOp | StrokeRectOp | FillCircleOp | FillEllipseOp |
	FillRoundedRectOp | FillPieOp | FillRingOp | FillGradientPolygonOp |
	FillGradientPolygonOklabOp | FillGradientPolygonStopsOp | FillGradientRectOp |
	FillGradientRectOklabOp | FillGradientRectStopsOp | FillRadialGradientOp |
	FillRadialGradientOklabOp | FillRadialGradientStopsOp | FillSlashRectOp | FillCheckerRectOp |
	FillTexRectOp | FillTexPolygonOp;

function validateGraphicsSources(operations: Span<GraphicsOp>): void {
	let source: TextureSource = WHITE_SOURCE;
	let premultiplied = false;
	let found = false;
	for (const op of operations) {
		let current: TextureSource = WHITE_SOURCE;
		let currentPremultiplied = false;
		match (op.kind) {
			"fillTexRect" | "fillTexPolygon" => {
				current = op.tile.source;
				currentPremultiplied = op.tile.alphaPremultiplied;
			}
			"fillRect" | "fillPolygon" | "fillConvex" | "fillTriangle" |
			"strokeLine" | "strokePoly" | "strokeRect" | "fillCircle" |
			"fillEllipse" | "fillRoundedRect" | "fillPie" | "fillRing" => {}
			"fillGradientPolygon" | "fillGradientPolygonOklab" | "fillGradientPolygonStops" |
			"fillGradientRect" | "fillGradientRectOklab" | "fillGradientRectStops" |
			"fillRadialGradient" | "fillRadialGradientOklab" | "fillRadialGradientStops" |
			"fillSlashRect" | "fillCheckerRect" => { continue; }
		}
		if (found && (!source.sameAs(current) || premultiplied !== currentPremultiplied)) {
			throw new Error("Graphics: mesh operations must share one TextureSource and alphaPremultiplied value");
		}
		source = current;
		premultiplied = currentPremultiplied;
		found = true;
	}
}

export function replayGraphics(node: NodeRef, operations: Span<GraphicsOp>): void {
	validateGraphicsSources(operations);
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
			"fillGradientPolygon" => {
				node.fillGradientPolygon(op.points, op.c0, op.c1, op.angle);
			}
			"fillGradientPolygonOklab" => {
				node.fillGradientPolygonOklab(op.points, op.c0, op.c1, op.angle);
			}
			"fillGradientPolygonStops" => {
				node.fillGradientPolygonStops(op.points, op.c0, op.cMiddle, op.c1,
					op.middle, op.angle, op.space);
			}
			"fillGradientRect" => {
				node.fillGradientRect(op.x, op.y, op.w, op.h, op.c0, op.c1, op.angle);
			}
			"fillGradientRectOklab" => {
				node.fillGradientRectOklab(op.x, op.y, op.w, op.h, op.c0, op.c1, op.angle);
			}
			"fillGradientRectStops" => {
				node.fillGradientRectStops(op.x, op.y, op.w, op.h, op.c0, op.cMiddle,
					op.c1, op.middle, op.angle, op.space);
			}
			"fillRadialGradient" => {
				node.fillRadialGradient(op.cx, op.cy, op.r, op.cInner, op.cOuter);
			}
			"fillRadialGradientOklab" => {
				node.fillRadialGradientOklab(op.cx, op.cy, op.r, op.cInner, op.cOuter);
			}
			"fillRadialGradientStops" => {
				node.fillRadialGradientStops(op.cx, op.cy, op.r, op.c0, op.cMiddle,
					op.c1, op.middle, op.space);
			}
			"fillSlashRect" => {
				node.fillSlashRect(op.x, op.y, op.w, op.h, op.background, op.stripe,
					op.spacing, op.width);
			}
			"fillCheckerRect" => {
				node.fillCheckerRect(op.x, op.y, op.w, op.h, op.a, op.b, op.cell);
			}
			"fillRing" => {
				node.fillRing(op.cx, op.cy, op.outerR, op.innerR,
					op.angleStart, op.angleLength, op.color);
			}
			"fillTexRect" => {
				node.fillTexRect(op.tile, op.x, op.y, op.w, op.h, op.color);
			}
			"fillTexPolygon" => {
				node.fillTexPolygon(op.tile, op.points, op.originX, op.originY,
					op.tileW, op.tileH, op.color);
			}
		}
	}
}
