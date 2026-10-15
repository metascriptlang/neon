import { accessor, createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Group, Mesh, Light } from "../../src/components/scene3d";
import { NodeId3D, NodeFlag, LightKind, nodeCount, isLive } from "../../../void/src/void3d/scene";
import { NO_MESH, releaseMesh } from "../../../void/src/void3d/draw";
import { added, litShape } from "../../../void/src/test/drawHelpers";
import { Vec3, vec3 } from "../../../void/src/math/math3d";

test "Group Mesh Light visibility pickability and names react through Void binders" {
	let handle: Scene3DHandle | null = null;
	let mesh = NO_MESH;
	const nodes: NodeId3D[] = [];
	const [visible, setVisible] = createSignal(false);
	const [pickable, setPickable] = createSignal(true);
	const [name, setName] = createSignal("first");
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => {
			handle = value; mesh = added(value.context, litShape());
		}}>
			<Group visible={visible()} pickable={pickable()} name={name()}
				ref={(value: NodeId3D): void => { nodes.push(value); }} />
			<Mesh mesh={mesh} visible={visible()} pickable={pickable()} name={name()}
				ref={(value: NodeId3D): void => { nodes.push(value); }} />
			<Light kind={LightKind.Point} visible={visible()} pickable={pickable()} name={name()}
				ref={(value: NodeId3D): void => { nodes.push(value); }} />
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	for (const id of nodes) {
		assert !handle.scene.nodes[id.index].flags.has(NodeFlag.Visible);
		assert handle.scene.nodes[id.index].flags.has(NodeFlag.Pickable);
		assert handle.scene.nodes[id.index].name === "first";
	}
	setVisible(true); setPickable(false); setName("second");
	for (const id of nodes) {
		assert handle.scene.nodes[id.index].flags.has(NodeFlag.Visible);
		assert !handle.scene.nodes[id.index].flags.has(NodeFlag.Pickable);
		assert handle.scene.nodes[id.index].name === "second";
	}
	const released = releaseMesh(handle.context, mesh);
	assert released.ok;
	dispose(); setVisible(false); setPickable(true); setName("late");
	assert handle.scene.closed && handle.context.closed && handle.scene.nodeCount() === 0;
	assert handle.context.meshHolders[mesh.index] === 0;
}

test "Omitted node flags preserve Void defaults and remount reads current values" {
	let handle: Scene3DHandle | null = null;
	const nodes: NodeId3D[] = [];
	const [shown, setShown] = createSignal(true);
	const [visible, setVisible] = createSignal(false);
	const [name, setName] = createSignal("before");
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { handle = value; }}>
			<Group ref={(value: NodeId3D): void => { nodes.push(value); }} />
			{Show({ when: accessor(() => shown()), children: element(
				<Group visible={visible()} name={name()}
					ref={(value: NodeId3D): void => { nodes.push(value); }} />
			) })}
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	assert handle.scene.nodes[nodes[0].index].flags.has(NodeFlag.Visible);
	assert !handle.scene.nodes[nodes[0].index].flags.has(NodeFlag.Pickable);
	assert handle.scene.nodes[nodes[0].index].name === "";
	setShown(false); setVisible(true); setName("after"); setShown(true);
	assert !handle.scene.isLive(nodes[1]);
	assert handle.scene.nodes[nodes[2].index].flags.has(NodeFlag.Visible);
	assert handle.scene.nodes[nodes[2].index].name === "after";
	dispose(); setShown(false); setVisible(false); setName("late");
	assert handle.scene.closed && handle.scene.nodeCount() === 0;
}

test "Scene3D ambient follows its signal without changing sibling scenes or Void defaults" {
	let first: Scene3DHandle | null = null;
	let second: Scene3DHandle | null = null;
	let defaults: Scene3DHandle | null = null;
	const [ambient, setAmbient] = createSignal<Vec3>(vec3(0.1, 0.2, 0.3));
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ambient={ambient()}
			ref={(value: Scene3DHandle): void => { first = value; }} />
		<Scene3D ambient={vec3(0.7, 0.8, 0.9)}
			ref={(value: Scene3DHandle): void => { second = value; }} />
		<Scene3D ref={(value: Scene3DHandle): void => { defaults = value; }} />
	</Void>), mockHost(), root as unknown as HostNode);
	if (first === null) { throw new Error("fixture: first ref did not mount"); }
	assert first.scene.ambientLight === vec3(0.1, 0.2, 0.3);
	if (second === null) { throw new Error("fixture: second ref did not mount"); }
	assert second.scene.ambientLight === vec3(0.7, 0.8, 0.9);
	if (defaults === null) { throw new Error("fixture: defaults ref did not mount"); }
	assert defaults.scene.ambientLight === vec3(0.5, 0.5, 0.5);
	setAmbient(vec3(0.4, 0.5, 0.6));
	assert first.scene.ambientLight === vec3(0.4, 0.5, 0.6);
	assert second.scene.ambientLight === vec3(0.7, 0.8, 0.9);
	assert defaults.scene.ambientLight === vec3(0.5, 0.5, 0.5);
	dispose(); setAmbient(vec3(1.0, 1.0, 1.0));
	assert first.scene.closed && second.scene.closed && defaults.scene.closed;
	assert first.context.closed && second.context.closed && defaults.context.closed;
}

