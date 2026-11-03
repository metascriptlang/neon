import { accessor, createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
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
	const refs: Scene3DHandle[] = [];
	let mesh = NO_MESH;
	const nodes: NodeId3D[] = [];
	const [visible, setVisible] = createSignal(false);
	const [pickable, setPickable] = createSignal(true);
	const [name, setName] = createSignal("first");
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => {
			refs.push(value); mesh = added(value.context, litShape());
		}}>
			<Group visible={visible()} pickable={pickable()} name={name()}
				ref={(value: NodeId3D): void => { nodes.push(value); }} />
			<Mesh mesh={mesh} visible={visible()} pickable={pickable()} name={name()}
				ref={(value: NodeId3D): void => { nodes.push(value); }} />
			<Light kind={LightKind.Point} visible={visible()} pickable={pickable()} name={name()}
				ref={(value: NodeId3D): void => { nodes.push(value); }} />
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	for (const id of nodes) {
		assert !handle.scene.nodes[id.index].flags.has(NodeFlag.Visible);
		assert handle.scene.nodes[id.index].flags.has(NodeFlag.Pickable);
		assert handle.scene.nodes[id.index].name === "first";
	}
	setVisible(true); setPickable(false); setName("second");
	flush();
	for (const id of nodes) {
		assert handle.scene.nodes[id.index].flags.has(NodeFlag.Visible);
		assert !handle.scene.nodes[id.index].flags.has(NodeFlag.Pickable);
		assert handle.scene.nodes[id.index].name === "second";
	}
	const released = releaseMesh(handle.context, mesh);
	assert released.ok;
	dispose(); setVisible(false); setPickable(true); setName("late");
	flush();
	assert handle.scene.closed && handle.context.closed && handle.scene.nodeCount() === 0;
	assert handle.context.meshHolders[mesh.index] === 0;
}

test "Omitted node flags preserve Void defaults and remount reads current values" {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	const [shown, setShown] = createSignal(true);
	const [visible, setVisible] = createSignal(false);
	const [name, setName] = createSignal("before");
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
			<Group ref={(value: NodeId3D): void => { nodes.push(value); }} />
			{Show({ when: accessor(() => shown()), children: element(
				<Group visible={visible()} name={name()}
					ref={(value: NodeId3D): void => { nodes.push(value); }} />
			) })}
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	assert handle.scene.nodes[nodes[0].index].flags.has(NodeFlag.Visible);
	assert !handle.scene.nodes[nodes[0].index].flags.has(NodeFlag.Pickable);
	assert handle.scene.nodes[nodes[0].index].name === "";
	setShown(false);
	flush();
	setVisible(true); setName("after"); setShown(true);
	flush();
	assert !handle.scene.isLive(nodes[1]);
	assert handle.scene.nodes[nodes[2].index].flags.has(NodeFlag.Visible);
	assert handle.scene.nodes[nodes[2].index].name === "after";
	dispose(); setShown(false); setVisible(false); setName("late");
	flush();
	assert handle.scene.closed && handle.scene.nodeCount() === 0;
}

test "Scene3D ambient follows its signal without changing sibling scenes or Void defaults" {
	const firstRefs: Scene3DHandle[] = [];
	const secondRefs: Scene3DHandle[] = [];
	const defaultRefs: Scene3DHandle[] = [];
	const [ambient, setAmbient] = createSignal<Vec3>(vec3(0.1, 0.2, 0.3));
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ambient={ambient()}
			ref={(value: Scene3DHandle): void => { firstRefs.push(value); }} />
		<Scene3D ambient={vec3(0.7, 0.8, 0.9)}
			ref={(value: Scene3DHandle): void => { secondRefs.push(value); }} />
		<Scene3D ref={(value: Scene3DHandle): void => { defaultRefs.push(value); }} />
	</Void>), mockHost(), root as unknown as HostNode);
	const first: Scene3DHandle | null = firstRefs.length === 0 ? null : firstRefs[0];
	const second: Scene3DHandle | null = secondRefs.length === 0 ? null : secondRefs[0];
	const defaults: Scene3DHandle | null = defaultRefs.length === 0 ? null : defaultRefs[0];
	if (first === null) { throw new Error("fixture: first ref did not mount"); }
	assert first.scene.ambientLight === vec3(0.1, 0.2, 0.3);
	if (second === null) { throw new Error("fixture: second ref did not mount"); }
	assert second.scene.ambientLight === vec3(0.7, 0.8, 0.9);
	if (defaults === null) { throw new Error("fixture: defaults ref did not mount"); }
	assert defaults.scene.ambientLight === vec3(0.5, 0.5, 0.5);
	setAmbient(vec3(0.4, 0.5, 0.6));
	flush();
	assert first.scene.ambientLight === vec3(0.4, 0.5, 0.6);
	assert second.scene.ambientLight === vec3(0.7, 0.8, 0.9);
	assert defaults.scene.ambientLight === vec3(0.5, 0.5, 0.5);
	dispose(); setAmbient(vec3(1.0, 1.0, 1.0));
	flush();
	assert first.scene.closed && second.scene.closed && defaults.scene.closed;
	assert first.context.closed && second.context.closed && defaults.context.closed;
}

test "Group and Mesh are created detached and attached once, before the sibling they were placed ahead of" {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	const seen: int32[] = [];
	let mesh = NO_MESH;
	const [shown, setShown] = createSignal(false);
	const rootChildren = (): int32 => {
		const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
		if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
		return handle.scene.nodes[handle.scene.root].children.length as int32;
	};
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => {
			refs.push(value); mesh = added(value.context, litShape());
		}}>
			{Show({ when: accessor(() => shown()), children: element(<>
				<Group name={(() => { seen.push(rootChildren()); return "group"; })()}
					ref={(value: NodeId3D): void => { nodes.push(value); }} />
				<Mesh mesh={mesh} name={(() => { seen.push(rootChildren()); return "mesh"; })()}
					ref={(value: NodeId3D): void => { nodes.push(value); }} />
			</>) })}
			<Group ref={(value: NodeId3D): void => { nodes.push(value); }} />
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	assert nodes.length === 1;
	setShown(true);
	flush();
	assert nodes.length === 3;
	assert seen.length === 2;
	assert seen[0] === 1, "a Group exists detached until placement attaches it";
	assert seen[1] === 1, "a Mesh exists detached until placement attaches it";
	const children = handle.scene.nodes[handle.scene.root].children;
	assert children.length === 3;
	assert children[0] === nodes[1].index && children[1] === nodes[2].index && children[2] === nodes[0].index;
	const released = releaseMesh(handle.context, mesh);
	assert released.ok;
	dispose();
	flush();
	assert handle.scene.closed;
}

