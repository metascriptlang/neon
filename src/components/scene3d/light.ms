import { Accessor } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { Vec3, vec3 } from "../../../../void/src/math/math3d";
import {
	LightKind, LightInstance, addLightNode, setLightPower, setLightColor, setLightRadius, setLightPriority,
} from "../../../../void/src/void3d/scene";
import { NodeProps, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren } from "./core";

export interface LightProps extends NodeProps {
	kind: Accessor<LightKind>;
	color?: Accessor<Vec3> | null;
	radius?: Accessor<float32> | null;
	power?: Accessor<float32> | null;
	priority?: Accessor<int32> | null;
}

export function Light(props: LightProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Light");
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
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}
