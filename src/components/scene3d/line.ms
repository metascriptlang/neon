import { Accessor, untrack } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { Color } from "../../../../void/src/void2d/types";
import { Vec3 } from "../../../../void/src/math/math3d";
import { Material, MaterialKind, UniformBlock } from "../../../../void/src/void3d/material";
import { Program, LINE_UNIFORM_LENGTH } from "../../../../void/src/void3d/gpu3d";
import { Rgba } from "../../../../void/src/void3d/meshData";
import { CameraView } from "../../../../void/src/void3d/camera";
import {
	DrawContext, MeshId, MaterialId, addMeshData, releaseMesh, releaseMaterial, writeUniforms,
} from "../../../../void/src/void3d/draw";
import { addMeshNode, setMeshOf } from "../../../../void/src/void3d/scene";
import {
	Graphics3D, GraphicsError, setGraphicsColorF, moveTo, lineTo, writeLineBlock,
} from "../../../../void/src/void3d/graphics3d";
import {
	NodeProps, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren, onBeforeRefresh,
	viewCamera, valueOr, addUniformMaterial,
} from "./core";

// points, color, lineWidth and segments are drei's Line props (Line.tsx:16-35). lineWidth is in
// pixels, as drei's LineMaterial without worldUnits, and segments reads the points as separate
// pairs, as LineSegments2. vertexColors and dashed are drei's and Void cannot draw them (a
// segment has one colour, and the line program has no dash), so a Line given one refuses it.
export interface LineProps extends NodeProps {
	points: Accessor<Vec3[]>;
	color?: Accessor<Color> | null;
	lineWidth?: Accessor<float32> | null;
	segments?: Accessor<boolean> | null;
	vertexColors?: Accessor<Color[]> | null;
	dashed?: Accessor<boolean> | null;
}

function refuse(reason: string): Error {
	return new Error("Line: " + reason);
}

function refuseUnmapped(props: LineProps): void {
	if (props.vertexColors !== null) {
		throw refuse("vertexColors has no counterpart; Void's line carries one colour per segment, so set color");
	}
	if (props.dashed !== null) {
		throw refuse("dashed has no counterpart; Void's line program draws solid lines only");
	}
}

function checkedWidth(width: float32): float32 {
	if (!(Number.isFinite(width) && width > 0.0)) { throw refuse("lineWidth must be a finite number of pixels above 0"); }
	return width;
}

function tintOf(color: Color): Rgba {
	if (!(Number.isFinite(color.r) && Number.isFinite(color.g) && Number.isFinite(color.b) && Number.isFinite(color.a))) {
		throw refuse("color must be finite");
	}
	if (color.a != 1.0) { throw refuse("color alpha must be 1; Void draws a line in the opaque phase"); }
	return { red: color.r, green: color.g, blue: color.b, alpha: color.a };
}

function drawn(result: Result<void, GraphicsError>, what: string): void {
	if (!result.ok) { throw refuse(what + " refused: " + result.error.toString()); }
}

function graphicsOf(points: Vec3[], segments: boolean, width: float32): Graphics3D {
	if (points.length < 2) { throw refuse("points needs at least 2 points, got " + points.length.toString()); }
	if (segments && points.length % 2 != 0) { throw refuse("segments reads points in pairs, got " + points.length.toString() + " points"); }
	for (let i = 0; i < points.length; i++) {
		const p = points[i];
		if (!(Number.isFinite(p.x) && Number.isFinite(p.y) && Number.isFinite(p.z))) {
			throw refuse("points[" + i.toString() + "] must be finite");
		}
	}
	let graphics = Graphics3D.create();
	graphics.width = width;
	drawn(setGraphicsColorF(graphics, 1.0, 1.0, 1.0, 1.0), "setGraphicsColorF");
	const step = segments ? 2 : 1;
	for (let i = 0; i + 1 < points.length; i += step) {
		if (i == 0 || segments) { drawn(moveTo(graphics, points[i].x, points[i].y, points[i].z), "moveTo points[" + i.toString() + "]"); }
		drawn(lineTo(graphics, points[i + 1].x, points[i + 1].y, points[i + 1].z), "lineTo points[" + (i + 1).toString() + "]");
	}
	return graphics;
}

export function Line(props: LineProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		refuseUnmapped(props);
		const scope = requireScene("Line");
		mountOwned((): void => {
			const state = scope.state;
			const scene = state.handle.scene;
			const context: DrawContext = state.handle.context;
			const local = localOf(props);
			const readSegments = (): boolean => valueOr<boolean>(props.segments, false);
			const readWidth = (): float32 => checkedWidth(valueOr<float32>(props.lineWidth, 1.0));
			const readColor = (): Rgba => tintOf(props.color === null ? { r: 1.0, g: 1.0, b: 1.0, a: 1.0 } : (props.color as () => Color)());
			let width = untrack(readWidth);
			let color = untrack(readColor);
			let graphics = graphicsOf(untrack(props.points), untrack(readSegments), width);
			let values: Vec<float32> = new Array(LINE_UNIFORM_LENGTH);
			const material: MaterialId = addUniformMaterial(context, "Line", values, (block: UniformBlock): Material => ({
				...Material.ofKind(Program.Line, MaterialKind.Opaque), uniforms: block,
			}));
			onCleanup((): void => {
				const released = releaseMaterial(context, material);
				if (!released.ok) { throw refuse("releaseMaterial failed: " + released.error.toString()); }
				state.invalidate();
			});
			const upload = (data: Graphics3D): MeshId => {
				const uploaded = addMeshData(context, data.data);
				if (!uploaded.ok) { throw refuse("addMeshData failed: " + uploaded.error.toString()); }
				return uploaded.value;
			};
			const first = upload(graphics);
			const placed = addMeshNode(scene, scope.parent, local, first, material);
			const firstReleased = releaseMesh(context, first);
			if (!placed.ok) { throw refuse("addMeshNode failed: " + placed.error.toString()); }
			if (!firstReleased.ok) { throw refuse("releaseMesh failed: " + firstReleased.error.toString()); }
			const node = placed.value;
			ownNode(state, node);
			createRenderEffect<[Vec3[], boolean]>(
				(prev: [Vec3[], boolean] | null): [Vec3[], boolean] => [props.points(), readSegments()],
				(value: [Vec3[], boolean], prev: [Vec3[], boolean] | null): Cleanup | null => {
					if (prev === null) { return null; }
					const next = graphicsOf(value[0], value[1], width);
					const mesh = upload(next);
					const changed = setMeshOf(scene, node, mesh);
					const released = releaseMesh(context, mesh);
					if (!changed.ok) { throw refuse("setMeshOf failed: " + changed.error.toString()); }
					if (!released.ok) { throw refuse("releaseMesh failed: " + released.error.toString()); }
					graphics = next;
					state.invalidate();
					return null;
				},
			);
			createRenderEffect<[float32, Rgba]>(
				(prev: [float32, Rgba] | null): [float32, Rgba] => [readWidth(), readColor()],
				(value: [float32, Rgba], prev: [float32, Rgba] | null): Cleanup | null => {
					if (prev === null) { return null; }
					width = value[0];
					color = value[1];
					graphics.width = width;
					state.invalidate();
					return null;
				},
			);
			onBeforeRefresh(state, (view: CameraView): void => {
				const world = viewCamera(state.handle);
				if (!world.ok) { throw refuse("the active camera has no world pose: " + world.error.toString()); }
				writeLineBlock(graphics, world.value, view, color, values);
				const written = writeUniforms(context, context.materials[material.index].uniforms, values);
				if (!written.ok) { throw refuse("writeUniforms failed: " + written.error.toString()); }
			});
			bindNode(state, node, props, local);
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}
