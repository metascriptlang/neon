import { Accessor } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { Vec3, vec3 } from "../../../../void/src/math/math3d";
import {
	LightKind, LightInstance, addLightNode, setLightPower, setLightColor, setLightRadius, setLightPriority,
} from "../../../../void/src/void3d/scene";
import { NodeProps, LightShadow, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren } from "./core";
import { DEFAULT_SHADOW_BIAS } from "../../../../void/src/void3d/dirShadowMap";

export interface LightProps extends NodeProps {
	kind: Accessor<LightKind>;
	color?: Accessor<Vec3> | null;
	radius?: Accessor<float32> | null;
	power?: Accessor<float32> | null;
	priority?: Accessor<int32> | null;
	castShadow?: Accessor<boolean> | null;
	shadowMapSize?: Accessor<int32> | null;
	shadowBias?: Accessor<float32> | null;
	shadowOpacity?: Accessor<float32> | null;
}

const DEFAULT_SHADOW_MAP_SIZE: int32 = 512;

function validShadow(shadow: LightShadow): boolean {
	return shadow.mapSize > 0 && Number.isFinite(shadow.bias) && shadow.opacity >= 0.0 && shadow.opacity <= 1.0;
}

export function Light(props: LightProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Light");
		if (props.castShadow === null && (props.shadowMapSize !== null || props.shadowBias !== null || props.shadowOpacity !== null)) {
			throw new Error("Light: shadowMapSize, shadowBias and shadowOpacity need castShadow");
		}
		mountOwned((): void => {
			const scene = scope.state.handle.scene;
			const local = localOf(props);
			const light: LightInstance = {
				kind: props.kind(),
				color: props.color === null ? vec3(1.0, 1.0, 1.0) : (props.color as () => Vec3)(),
				radius: props.radius === null ? 10.0 : (props.radius as () => float32)(),
				power: props.power === null ? 1.0 : (props.power as () => float32)(),
				priority: props.priority === null ? 0 : (props.priority as () => int32)(),
			};
			const node = addLightNode(scene, scope.parent, local, light);
			ownNode(scope.state, node);
			bindNode(scope.state, node, props, local);
			let color = light.color;
			let radius = light.radius;
			let priority = light.priority;
			createRenderEffect<LightInstance>(
				(prev: LightInstance | null): LightInstance => ({
					...light, kind: props.kind(),
					color: props.color === null ? light.color : (props.color as () => Vec3)(),
					radius: props.radius === null ? light.radius : (props.radius as () => float32)(),
					priority: props.priority === null ? light.priority : (props.priority as () => int32)(),
				}),
				(value: LightInstance, prev: LightInstance | null): Cleanup | null => {
					if (value.kind !== light.kind) { throw new Error("Light: kind cannot change; Void has no light-kind binder"); }
					let changed = false;
					if (value.color !== color) {
						setLightColor(scene, node, value.color);
						color = value.color;
						changed = true;
					}
					if (value.radius !== radius) {
						setLightRadius(scene, node, value.radius);
						radius = value.radius;
						changed = true;
					}
					if (value.priority !== priority) {
						setLightPriority(scene, node, value.priority);
						priority = value.priority;
						changed = true;
					}
					if (changed) { scope.state.invalidate(); }
					return null;
				},
			);
			if (props.power !== null) {
				let power = light.power;
				createRenderEffect<float32>(
					(prev: float32 | null): float32 => (props.power as () => float32)(),
					(next: float32, prev: float32 | null): Cleanup | null => {
						if (next !== power) {
							setLightPower(scene, node, next);
							power = next;
							scope.state.invalidate();
						}
						return null;
					},
				);
			}
			if (props.castShadow !== null) {
				const state = scope.state;
				onCleanup((): void => { state.shadowOf(node, null); });
				createRenderEffect<LightShadow | null>(
					(prev: LightShadow | null | null): LightShadow | null => (props.castShadow as () => boolean)() ? {
						mapSize: props.shadowMapSize === null ? DEFAULT_SHADOW_MAP_SIZE : (props.shadowMapSize as () => int32)(),
						bias: props.shadowBias === null ? DEFAULT_SHADOW_BIAS : (props.shadowBias as () => float32)(),
						opacity: props.shadowOpacity === null ? 1.0 : (props.shadowOpacity as () => float32)(),
					} : null,
					(value: LightShadow | null, prev: LightShadow | null | null): Cleanup | null => {
						if (value !== null && light.kind !== LightKind.Directional) {
							throw new Error("Light: castShadow needs a Directional light; Void's shadow map follows the directional light");
						}
						if (value !== null && !validShadow(value as LightShadow)) { throw new Error("Light: invalid shadow settings"); }
						state.shadowOf(node, value);
						return null;
					},
				);
			}
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}
