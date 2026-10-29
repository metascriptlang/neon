import { Accessor, accessor } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { Vec3, vec3 } from "../../../../void/src/math/math3d";
import {
	LightKind, LightInstance, LightShape, addLightNode, setLightPower, setLightColor, setLightRadius,
	setLightCookie,
} from "../../../../void/src/void3d/scene";
import { TextureId, NO_TEXTURE } from "../../../../void/src/void3d/texture";
import {
	SpotLightShape, RectangleLightShape, CapsuleLightShape, validateSpot, validateRectangle, validateCapsule, coneCosines,
} from "../../../../void/src/void3d/lightShape";
import {
	NodeProps, LightShadow, LightSlot, SceneState, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren, valueOr,
} from "./core";
import { DEFAULT_SHADOW_BIAS } from "../../../../void/src/void3d/dirShadowMap";

export interface LightProps extends NodeProps {
	kind: Accessor<LightKind>;
	color?: Accessor<Vec3> | null;
	radius?: Accessor<float32> | null;
	power?: Accessor<float32> | null;
	shape?: Accessor<LightShape> | null;
	cookie?: Accessor<TextureId> | null;
	castShadow?: Accessor<boolean> | null;
	shadowMapSize?: Accessor<int32> | null;
	shadowBias?: Accessor<float32> | null;
	shadowNormalBias?: Accessor<float32> | null;
	shadowRadius?: Accessor<float32> | null;
	shadowOpacity?: Accessor<float32> | null;
}

const DEFAULT_SHADOW_MAP_SIZE: int32 = 512;
const DEFAULT_SHADOW_RADIUS: float32 = 1.0;
const NO_SHAPE: LightShape = { angle: 0.0, verticalAngle: 0.0, falloff: 0.0, width: 0.0, height: 0.0, length: 0.0, capsuleRadius: 0.0 };
const AHEAD: Vec3 = vec3(0.0, 0.0, 1.0);
const RIGHT: Vec3 = vec3(1.0, 0.0, 0.0);
const UP: Vec3 = vec3(0.0, 1.0, 0.0);
const ORIGIN: Vec3 = vec3(0.0, 0.0, 0.0);

function validShadow(shadow: LightShadow): boolean {
	return shadow.mapSize > 0 && Number.isFinite(shadow.bias) && Number.isFinite(shadow.normalBias) &&
		Number.isFinite(shadow.radius) && shadow.radius >= 0.0 && shadow.opacity >= 0.0 && shadow.opacity <= 1.0;
}

function shaped(kind: LightKind): boolean {
	return kind === LightKind.Spot || kind === LightKind.Rectangle || kind === LightKind.Capsule;
}

function shadowSlot(kind: LightKind): LightSlot {
	return kind === LightKind.Directional ? LightSlot.Sun : kind === LightKind.Spot ? LightSlot.Spot : LightSlot.Cube;
}

function shapeProblem(kind: LightKind, shape: LightShape, range: float32): string | null {
	if (kind === LightKind.Spot) {
		const spot: SpotLightShape = {
			position: ORIGIN, forward: AHEAD, range: range, cone: { fullAngleRadians: shape.angle, falloffRadians: shape.falloff },
		};
		const checked = spot.validateSpot();
		return checked.ok ? null : checked.error.toString() + "; a spot needs 0 < angle < PI/2 and 0 < penumbra <= 1";
	}
	if (kind === LightKind.Rectangle) {
		const rectangle: RectangleLightShape = {
			position: ORIGIN, forward: AHEAD, right: RIGHT, up: UP, halfWidth: shape.width * 0.5, halfHeight: shape.height * 0.5,
			horizontal: { fullAngleRadians: shape.angle, falloffRadians: shape.falloff },
			vertical: { fullAngleRadians: shape.verticalAngle, falloffRadians: shape.falloff },
			range: range,
		};
		const checked = rectangle.validateRectangle();
		if (!checked.ok) { return checked.error.toString(); }
		const horizontal = rectangle.horizontal.coneCosines();
		if (!horizontal.ok) { return horizontal.error.toString(); }
		const vertical = rectangle.vertical.coneCosines();
		return vertical.ok ? null : vertical.error.toString();
	}
	const capsule: CapsuleLightShape = {
		position: ORIGIN, axis: AHEAD, halfLength: shape.length * 0.5, radius: shape.capsuleRadius, range: range,
	};
	const checked = capsule.validateCapsule();
	return checked.ok ? null : checked.error.toString();
}

function bindLight<T>(state: SceneState, read: () => T, initial: T, write: (value: T) => void): void {
	let held = initial;
	createRenderEffect<T>(
		(prev: T | null): T => read(),
		(value: T, prev: T | null): Cleanup | null => {
			if (value !== held) {
				write(value);
				held = value;
				state.invalidate();
			}
			return null;
		},
	);
}

export function Light(props: LightProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Light");
		const kind = props.kind();
		const name = kind.toString();
		if (shaped(kind) && props.shape === null) { throw new Error("Light: kind " + name + " needs shape; Void reads a zero cone and refuses it every frame"); }
		if (!shaped(kind) && props.shape !== null) { throw new Error("Light: shape needs a Spot, Rectangle or Capsule kind, not " + name); }
		if (props.cookie !== null && kind !== LightKind.Spot) { throw new Error("Light: cookie needs a Spot light, not " + name + " (LightError.UncookableLight)"); }
		if (props.castShadow === null && (props.shadowMapSize !== null || props.shadowBias !== null || props.shadowNormalBias !== null ||
			props.shadowRadius !== null || props.shadowOpacity !== null)) {
			throw new Error("Light: shadowMapSize, shadowBias, shadowNormalBias, shadowRadius and shadowOpacity need castShadow");
		}
		mountOwned((): void => {
			const state = scope.state;
			const scene = state.handle.scene;
			const local = localOf(props);
			const radius = valueOr<float32>(props.radius, 10.0);
			const shape = valueOr<LightShape>(props.shape, NO_SHAPE);
			if (props.shape !== null) {
				const problem = shapeProblem(kind, shape, radius);
				if (problem !== null) { throw new Error("Light: kind " + name + " refuses its shape: " + problem); }
			}
			const cookie = valueOr<TextureId>(props.cookie, NO_TEXTURE);
			const light: LightInstance = {
				kind: kind,
				color: valueOr<Vec3>(props.color, vec3(1.0, 1.0, 1.0)),
				radius: radius,
				power: valueOr<float32>(props.power, 1.0),
				shape: shape,
				shadows: kind !== LightKind.Directional && valueOr<boolean>(props.castShadow, false),
				cookie: cookie,
			};
			const node = addLightNode(scene, scope.parent, local, light);
			ownNode(state, node);
			onCleanup((): void => {
				state.releaseLight(LightSlot.Directional, node);
				state.releaseLight(LightSlot.Cookie, node);
			});
			bindNode(state, node, props, local);
			if (kind === LightKind.Directional) { state.claimLight(LightSlot.Directional, node); }
			if (cookie.isTexture()) { state.claimLight(LightSlot.Cookie, node); }
			createRenderEffect<LightKind>(
				(prev: LightKind | null): LightKind => props.kind(),
				(value: LightKind, prev: LightKind | null): Cleanup | null => {
					if (value !== kind) { throw new Error("Light: kind cannot change; Void has no light-kind binder"); }
					return null;
				},
			);
			if (props.shape !== null) {
				createRenderEffect<LightShape>(
					(prev: LightShape | null): LightShape => (props.shape as () => LightShape)(),
					(value: LightShape, prev: LightShape | null): Cleanup | null => {
						if (value !== shape) { throw new Error("Light: shape is fixed at mount; Void has no light-shape binder"); }
						return null;
					},
				);
			}
			if (props.color !== null) {
				bindLight<Vec3>(state, props.color as () => Vec3, light.color, (value: Vec3): void => { setLightColor(scene, node, value); });
			}
			if (props.radius !== null) {
				bindLight<float32>(state, props.radius as () => float32, light.radius, (value: float32): void => { setLightRadius(scene, node, value); });
			}
			if (props.power !== null) {
				bindLight<float32>(state, props.power as () => float32, light.power, (value: float32): void => { setLightPower(scene, node, value); });
			}
			if (props.cookie !== null) {
				bindLight<TextureId>(state, props.cookie as () => TextureId, cookie, (value: TextureId): void => {
					if (value.isTexture()) { state.claimLight(LightSlot.Cookie, node); } else { state.releaseLight(LightSlot.Cookie, node); }
					setLightCookie(scene, node, value);
				});
			}
			if (props.castShadow !== null) {
				const slot = shadowSlot(kind);
				onCleanup((): void => { state.shadowOf(node, slot, null); });
				createRenderEffect<LightShadow | null>(
					(prev: LightShadow | null | null): LightShadow | null => (props.castShadow as () => boolean)() ? {
						mapSize: valueOr<int32>(props.shadowMapSize, DEFAULT_SHADOW_MAP_SIZE),
						bias: valueOr<float32>(props.shadowBias, DEFAULT_SHADOW_BIAS),
						normalBias: valueOr<float32>(props.shadowNormalBias, 0.0),
						radius: valueOr<float32>(props.shadowRadius, DEFAULT_SHADOW_RADIUS),
						opacity: valueOr<float32>(props.shadowOpacity, 1.0),
					} : null,
					(value: LightShadow | null, prev: LightShadow | null | null): Cleanup | null => {
						if (kind !== LightKind.Directional && (value !== null) !== light.shadows) {
							throw new Error("Light: castShadow is fixed at mount on a " + name + " light; Void has no light-shadows binder");
						}
						if (value !== null && !validShadow(value as LightShadow)) { throw new Error("Light: invalid shadow settings"); }
						state.shadowOf(node, slot, value);
						return null;
					},
				);
			}
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}

export interface DirectionalLightProps extends NodeProps {
	color?: Accessor<Vec3> | null;
	power?: Accessor<float32> | null;
	castShadow?: Accessor<boolean> | null;
	shadowMapSize?: Accessor<int32> | null;
	shadowBias?: Accessor<float32> | null;
	shadowNormalBias?: Accessor<float32> | null;
	shadowRadius?: Accessor<float32> | null;
	shadowOpacity?: Accessor<float32> | null;
}

export interface PointLightProps extends NodeProps {
	color?: Accessor<Vec3> | null;
	radius?: Accessor<float32> | null;
	power?: Accessor<float32> | null;
	castShadow?: Accessor<boolean> | null;
	shadowMapSize?: Accessor<int32> | null;
	shadowBias?: Accessor<float32> | null;
	shadowNormalBias?: Accessor<float32> | null;
	shadowRadius?: Accessor<float32> | null;
	shadowOpacity?: Accessor<float32> | null;
}

export interface SpotLightProps extends NodeProps {
	angle: Accessor<float32>;
	penumbra: Accessor<float32>;
	distance: Accessor<float32>;
	color?: Accessor<Vec3> | null;
	power?: Accessor<float32> | null;
	map?: Accessor<TextureId> | null;
	castShadow?: Accessor<boolean> | null;
	shadowMapSize?: Accessor<int32> | null;
	shadowBias?: Accessor<float32> | null;
	shadowNormalBias?: Accessor<float32> | null;
	shadowRadius?: Accessor<float32> | null;
	shadowOpacity?: Accessor<float32> | null;
}

export function DirectionalLight(props: DirectionalLightProps): NeonNode {
	return Light({
		kind: accessor((): LightKind => LightKind.Directional), color: props.color, radius: null, power: props.power,
		shape: null, cookie: null,
		castShadow: props.castShadow, shadowMapSize: props.shadowMapSize, shadowBias: props.shadowBias,
		shadowNormalBias: props.shadowNormalBias, shadowRadius: props.shadowRadius, shadowOpacity: props.shadowOpacity,
		position: props.position, rotation: props.rotation, scale: props.scale, transform: props.transform,
		visible: props.visible, pickable: props.pickable, layers: props.layers, renderOrder: props.renderOrder,
		name: props.name, ref: props.ref, children: props.children,
	});
}

export function PointLight(props: PointLightProps): NeonNode {
	return Light({
		kind: accessor((): LightKind => LightKind.Point), color: props.color, radius: props.radius, power: props.power,
		shape: null, cookie: null,
		castShadow: props.castShadow, shadowMapSize: props.shadowMapSize, shadowBias: props.shadowBias,
		shadowNormalBias: props.shadowNormalBias, shadowRadius: props.shadowRadius, shadowOpacity: props.shadowOpacity,
		position: props.position, rotation: props.rotation, scale: props.scale, transform: props.transform,
		visible: props.visible, pickable: props.pickable, layers: props.layers, renderOrder: props.renderOrder,
		name: props.name, ref: props.ref, children: props.children,
	});
}

export function SpotLight(props: SpotLightProps): NeonNode {
	return Light({
		kind: accessor((): LightKind => LightKind.Spot), color: props.color, radius: props.distance, power: props.power,
		shape: accessor((): LightShape => {
			const half = props.angle();
			return { ...NO_SHAPE, angle: half * 2.0, falloff: half * (1.0 - props.penumbra()) };
		}),
		cookie: props.map,
		castShadow: props.castShadow, shadowMapSize: props.shadowMapSize, shadowBias: props.shadowBias,
		shadowNormalBias: props.shadowNormalBias, shadowRadius: props.shadowRadius, shadowOpacity: props.shadowOpacity,
		position: props.position, rotation: props.rotation, scale: props.scale, transform: props.transform,
		visible: props.visible, pickable: props.pickable, layers: props.layers, renderOrder: props.renderOrder,
		name: props.name, ref: props.ref, children: props.children,
	});
}
