import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { addGroup } from "../../../../void/src/void3d/scene";
import { NodeProps, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren } from "./core";

export function Group(props: NodeProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Group");
		mountOwned((): void => {
			const scene = scope.state.handle.scene;
			const local = localOf(props);
			const node = addGroup(scene, scope.parent, local);
			ownNode(scope.state, node);
			bindNode(scope.state, node, props, local);
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}
