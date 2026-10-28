import { Color } from "../../../void/src/void2d/types";
import {
	NodeRef,
	local,
	paint,
	setAlpha,
	setColor,
	setPivot,
	setRotation,
	setScale,
	setScaleX,
	setScaleY,
	setX,
	setY,
} from "../../../void/src/void2d/node";
import { NodeId3D, Scene3D, Transform3D, liveRow, setLocal } from "../../../void/src/void3d/scene";
import { Quat, eulerQuat } from "../../../void/src/math/math3d";
import { Clock, ManualClock } from "./clock";
import { MotionValue, ValueKind, colorValue, numberValue } from "./document";
import { MotionBinding } from "./player";

export class VoidClock {
	private manual: ManualClock = new ManualClock();

	get clock(): Clock {
		return this.manual.clock;
	}

	tick(dt: float32): void {
		this.manual.advance((dt as float64) * 1000);
	}

	pending(): int32 {
		return this.manual.pending();
	}
}

function fail(message: string): never {
	throw new Error("motion: " + message);
}

function numberBinding(
	slot: string,
	property: string,
	write: (value: float32) => void,
	read: () => float64,
): MotionBinding {
	return {
		slot,
		property,
		write: (value: MotionValue): void => {
			if (value.kind !== ValueKind.Number) { fail(slot + "." + property + " is bound as a number"); }
			write(value.number as float32);
		},
		read: (): MotionValue => numberValue(read()),
	};
}

function uniformScale(slot: string, axes: float32[]): float64 {
	for (const axis of axes) {
		if (axis !== axes[0]) {
			fail(slot + ".scale reads a non-uniform scale; bind its axes instead");
		}
	}
	return axes[0];
}

function refuseScaleOverlap(slot: string, properties: string[]): void {
	if (!properties.includes("scale")) { return; }
	for (const property of properties) {
		if (property !== "scale" && property.startsWith("scale")) {
			fail(slot + ".scale and " + slot + "." + property + " both write one scale");
		}
	}
}

function nodeBinding(slot: string, node: NodeRef, property: string): MotionBinding {
	switch (property) {
		case "x":
			return numberBinding(slot, property, (v: float32): void => { node.setX(v); }, (): float64 => node.local().x);
		case "y":
			return numberBinding(slot, property, (v: float32): void => { node.setY(v); }, (): float64 => node.local().y);
		case "rotation":
			return numberBinding(
				slot, property,
				(v: float32): void => { node.setRotation(v); },
				(): float64 => node.local().rotation,
			);
		case "scale":
			return numberBinding(
				slot, property,
				(v: float32): void => { node.setScale(v); },
				(): float64 => uniformScale(slot, [node.local().scaleX, node.local().scaleY]),
			);
		case "scaleX":
			return numberBinding(
				slot, property,
				(v: float32): void => { node.setScaleX(v); },
				(): float64 => node.local().scaleX,
			);
		case "scaleY":
			return numberBinding(
				slot, property,
				(v: float32): void => { node.setScaleY(v); },
				(): float64 => node.local().scaleY,
			);
		case "pivotX":
			return numberBinding(
				slot, property,
				(v: float32): void => { node.setPivot(v, node.local().pivotY); },
				(): float64 => node.local().pivotX,
			);
		case "pivotY":
			return numberBinding(
				slot, property,
				(v: float32): void => { node.setPivot(node.local().pivotX, v); },
				(): float64 => node.local().pivotY,
			);
		case "alpha":
			return numberBinding(
				slot, property,
				(v: float32): void => { node.setAlpha(v); },
				(): float64 => node.paint().alpha,
			);
		case "color":
			return {
				slot,
				property,
				write: (value: MotionValue): void => {
					if (value.kind !== ValueKind.Color) { fail(slot + "." + property + " is bound as a colour"); }
					const c = value.color;
					const color: Color = { r: c.r as float32, g: c.g as float32, b: c.b as float32, a: c.a as float32 };
					node.setColor(color);
				},
				read: (): MotionValue => {
					const c = node.paint().color;
					return colorValue(c.r, c.g, c.b, c.a);
				},
			};
		default:
			fail(slot + "." + property + " is not a Void 2D node property");
	}
}

struct Euler {
	x: float32;
	y: float32;
	z: float32;
}

function eulerOf(q: Quat): Euler {
	const sinY = Math.min(1, Math.max(-1, 2 * (q.w * q.y - q.z * q.x)));
	return {
		x: Math.atan2(2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y)) as float32,
		y: Math.asin(sinY) as float32,
		z: Math.atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z)) as float32,
	};
}

function objectBinding(slot: string, scene: Scene3D, id: NodeId3D, property: string): MotionBinding {
	const call = "motion " + slot + "." + property;
	const current = (): Transform3D => scene.nodes[scene.liveRow(id, call)].local;
	const put = (next: Transform3D): void => { setLocal(scene, id, next); };
	const rotate = (edit: (angles: Euler) => Euler): void => {
		const t = current();
		const e = edit(eulerOf(t.rotation));
		put({ ...t, rotation: eulerQuat(e.x, e.y, e.z) });
	};
	switch (property) {
		case "x":
			return numberBinding(
				slot, property,
				(v: float32): void => { const t = current(); put({ ...t, position: { ...t.position, x: v } }); },
				(): float64 => current().position.x,
			);
		case "y":
			return numberBinding(
				slot, property,
				(v: float32): void => { const t = current(); put({ ...t, position: { ...t.position, y: v } }); },
				(): float64 => current().position.y,
			);
		case "z":
			return numberBinding(
				slot, property,
				(v: float32): void => { const t = current(); put({ ...t, position: { ...t.position, z: v } }); },
				(): float64 => current().position.z,
			);
		case "rotationX":
			return numberBinding(
				slot, property,
				(v: float32): void => { rotate((e: Euler): Euler => ({ ...e, x: v })); },
				(): float64 => eulerOf(current().rotation).x,
			);
		case "rotationY":
			return numberBinding(
				slot, property,
				(v: float32): void => { rotate((e: Euler): Euler => ({ ...e, y: v })); },
				(): float64 => eulerOf(current().rotation).y,
			);
		case "rotationZ":
			return numberBinding(
				slot, property,
				(v: float32): void => { rotate((e: Euler): Euler => ({ ...e, z: v })); },
				(): float64 => eulerOf(current().rotation).z,
			);
		case "scale":
			return numberBinding(
				slot, property,
				(v: float32): void => { put({ ...current(), scale: { x: v, y: v, z: v } }); },
				(): float64 => {
					const s = current().scale;
					return uniformScale(slot, [s.x, s.y, s.z]);
				},
			);
		case "scaleX":
			return numberBinding(
				slot, property,
				(v: float32): void => { const t = current(); put({ ...t, scale: { ...t.scale, x: v } }); },
				(): float64 => current().scale.x,
			);
		case "scaleY":
			return numberBinding(
				slot, property,
				(v: float32): void => { const t = current(); put({ ...t, scale: { ...t.scale, y: v } }); },
				(): float64 => current().scale.y,
			);
		case "scaleZ":
			return numberBinding(
				slot, property,
				(v: float32): void => { const t = current(); put({ ...t, scale: { ...t.scale, z: v } }); },
				(): float64 => current().scale.z,
			);
		default:
			fail(slot + "." + property + " is not a Void 3D object property");
	}
}

export class VoidBindings {
	bindings: MotionBinding[] = [];

	node(slot: string, node: NodeRef, properties: string[]): void {
		refuseScaleOverlap(slot, properties);
		for (const property of properties) { this.bindings.push(nodeBinding(slot, node, property)); }
	}

	object(slot: string, scene: Scene3D, id: NodeId3D, properties: string[]): void {
		refuseScaleOverlap(slot, properties);
		for (const property of properties) { this.bindings.push(objectBinding(slot, scene, id, property)); }
	}
}
