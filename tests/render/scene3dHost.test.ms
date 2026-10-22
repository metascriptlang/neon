import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { createRenderEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show, For, Errored } from "../../src/macros/ui/flow";
import { Host, HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { NeonNode } from "../../src/render/hostTypes";
import { Void } from "../../src/components/primitives";
import {
	Scene3D, Scene3DHandle, Group, Mesh, Camera3D, Node, NodeProps, viewCamera,
	useScene3D, useSceneNode, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren,
} from "../../src/components/scene3d";
import {
	Scene3D as VoidScene3D, NodeId3D, NodeFlag, NO_NODE_ID, NO_NODE_3D, Transform3D,
	addGroup, remove, setName, refresh, isLive,
} from "../../../void/src/void3d/scene";
import { DrawItem, NO_MESH, releaseMesh } from "../../../void/src/void3d/draw";
import { added, litShape } from "../../../void/src/test/drawHelpers";
import { HOST_MOVE_CONTRACT, RECONCILE_CONTRACT, hostMoveContract, reconcileContract } from "./hostContract";

function namesUnder(scene: VoidScene3D, row: int32): string {
	let out = "";
	for (const child of scene.nodes[row].children) { out = out + scene.nodes[child].name; }
	return out;
}

function drawn(scene: VoidScene3D, id: NodeId3D): boolean {
	for (let at = id.index; at != NO_NODE_3D; at = scene.nodes[at].parent) {
		if (at == scene.root) { return true; }
	}
	return false;
}

function hasCamera(handle: Scene3DHandle): boolean {
	const camera = handle.camera;
	return camera !== null;
}

function only(refs: Scene3DHandle[]): Scene3DHandle {
	if (refs.length !== 1) { throw new Error("fixture: Scene3D ref ran " + refs.length.toString() + " times"); }
	return refs[0];
}

test "Show and keyed For inside Scene3D keep JSX order in Void, and a reorder moves the same nodes" {
	const refs: Scene3DHandle[] = [];
	const ids: NodeId3D[] = [];
	const [shown, setShown] = createSignal(false);
	const [items, setItems] = createSignal<string[]>(["x", "y", "z"]);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
			<Group name={"a"} />
			{Show({ when: accessor(() => shown()), children: element(<Group name={"b"} />) })}
			{For({ each: accessor(() => items()), children: (item: string, index: Accessor<number>): NeonNode => element(
				<Group name={item} ref={(value: NodeId3D): void => { ids.push(value); }} />
			) })}
			<Group name={"c"} />
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const scene = only(refs).scene;
	assert namesUnder(scene, scene.root) === "axyzc", namesUnder(scene, scene.root);
	setShown(true); flush();
	assert namesUnder(scene, scene.root) === "abxyzc", namesUnder(scene, scene.root);
	setItems(["z", "x", "y"]); flush();
	assert namesUnder(scene, scene.root) === "abzxyc", namesUnder(scene, scene.root);
	assert ids.length === 3 && scene.isLive(ids[0]) && scene.isLive(ids[1]) && scene.isLive(ids[2]), "the reorder moved, not rebuilt";
	setShown(false); setItems(["y"]); flush();
	assert namesUnder(scene, scene.root) === "ayc", namesUnder(scene, scene.root);
	assert !scene.isLive(ids[0]) && !scene.isLive(ids[2]), "dropped rows free their Void nodes";
	dispose();
	assert scene.closed;
}

test "the Scene3D host keeps the move and reconcile contracts and refuses text" {
	const refs: Scene3DHandle[] = [];
	const hosts: Host[] = [];
	const probe: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => { hosts.push(host); };
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>{probe}</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const host = hosts[0];
	const moves = hostMoveContract(host);
	assert moves === HOST_MOVE_CONTRACT, moves;
	const rows = reconcileContract(host);
	assert rows === RECONCILE_CONTRACT, rows;
	let refused = false;
	try { const t = host.createText("hi"); } catch (e) { refused = true; }
	assert refused, "text has no 3D node";
	dispose();
}

function failsWhenOne(a: () => int32): void {
	createRenderEffect<int32>(
		(p: int32 | null): int32 => a(),
		(v: int32, p: int32 | null): Cleanup | null => { if (v === 1) { throw new Error("late"); } return null; },
	);
}

test "content parked by Errored leaves the drawn scene and returns with the visibility it had" {
	const refs: Scene3DHandle[] = [];
	const ids: NodeId3D[] = [];
	const [a, setA] = createSignal(0);
	const [lit, setLit] = createSignal(false);
	let mesh = NO_MESH;
	let again: (() => void) | null = null;
	const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		failsWhenOne(a);
		element(<Mesh mesh={mesh} name={"m"} ref={(value: NodeId3D): void => { ids.push(value); }} />)(host, parent, before);
		element(<Group name={"g"} visible={lit()} ref={(value: NodeId3D): void => { ids.push(value); }} />)(host, parent, before);
		element(<Camera3D active={true} name={"cam"} ref={(value: NodeId3D): void => { ids.push(value); }} />)(host, parent, before);
	};
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = added(value.context, litShape()); }}>
			{Errored({
				children: content,
				fallback: (err: Accessor<Error>, reset: () => void): NeonNode => { again = reset; return element(<Group name={"f"} />); },
			})}
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const handle = only(refs);
	const scene = handle.scene;
	assert releaseMesh(handle.context, mesh).ok;
	let items: Vec<DrawItem> = [];
	assert refresh(scene, items) === 1 && hasCamera(handle);
	assert namesUnder(scene, scene.root) === "mgcam", namesUnder(scene, scene.root);
	setA(1); flush();
	assert namesUnder(scene, scene.root) === "f", namesUnder(scene, scene.root);
	for (const id of ids) { assert scene.isLive(id) && !drawn(scene, id), "parked content is alive and out of the drawn tree"; }
	assert refresh(scene, items) === 0, "a parked mesh is not drawn";
	assert !hasCamera(handle) && viewCamera(handle).ok, "a parked camera gives the view back";
	setLit(true); flush();
	setA(0); flush();
	(again as () => void)();
	flush();
	assert namesUnder(scene, scene.root) === "mgcam", namesUnder(scene, scene.root);
	assert ids.length === 3, "reset brought back the same nodes";
	assert refresh(scene, items) === 1 && hasCamera(handle) && viewCamera(handle).ok;
	assert scene.nodes[ids[0].index].flags.has(NodeFlag.Visible), "the shown mesh is visible again";
	assert scene.nodes[ids[1].index].flags.has(NodeFlag.Visible), "a visibility change made while parked holds";
	setLit(false); flush();
	assert !scene.nodes[ids[1].index].flags.has(NodeFlag.Visible);
	dispose();
	assert scene.closed && handle.context.closed;
}

function Marker(props: NodeProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Marker");
		mountOwned((): void => {
			const local = localOf(props);
			const node = addGroup(scope.state.handle.scene, scope.parent, local);
			ownNode(scope.state, node);
			bindNode(scope.state, node, props, local);
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}

test "a library element built from the exported helpers parents and orders like a built-in one" {
	const refs: Scene3DHandle[] = [];
	const marks: NodeId3D[] = [];
	const parents: NodeId3D[] = [];
	const handles: Scene3DHandle[] = [];
	const [on, setOn] = createSignal(false);
	const probe: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		parents.push(useSceneNode());
		handles.push(useScene3D());
	};
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
			<Group name={"a"} />
			{Show({ when: accessor(() => on()), children: element(
				<Marker name={"m"} ref={(value: NodeId3D): void => { marks.push(value); }}>
					<Group name={"k"} />
					{probe}
				</Marker>
			) })}
			<Group name={"c"} />
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const handle = only(refs);
	const scene = handle.scene;
	setOn(true); flush();
	assert namesUnder(scene, scene.root) === "amc", namesUnder(scene, scene.root);
	assert namesUnder(scene, marks[0].index) === "k", namesUnder(scene, marks[0].index);
	assert parents.length === 1 && parents[0] === marks[0], "useSceneNode answers the element's node";
	assert handles[0] === handle, "useScene3D answers the scene's handle";
	handles[0].invalidate();
	setOn(false); flush();
	assert !scene.isLive(marks[0]) && namesUnder(scene, scene.root) === "ac";
	dispose();
}

test "Node places an app-made node, mounts its children under it, and gives it back without freeing it" {
	const refs: Scene3DHandle[] = [];
	const groups: NodeId3D[] = [];
	const kids: NodeId3D[] = [];
	let kept = NO_NODE_ID;
	let loose = NO_NODE_ID;
	const [on, setOn] = createSignal(true);
	const [shown, setShown] = createSignal(false);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => {
			refs.push(value);
			const scene = value.scene;
			kept = addGroup(scene, scene.rootId(), Transform3D.identity());
			setName(scene, kept, "k");
			const after = addGroup(scene, scene.rootId(), Transform3D.identity());
			setName(scene, after, "s");
			loose = addGroup(scene, null, Transform3D.identity());
			setName(scene, loose, "l");
		}}>
			<Group name={"g"} ref={(value: NodeId3D): void => { groups.push(value); }}>
				{Show({ when: accessor(() => on()), children: element(
					<Node id={kept} visible={shown()}>
						<Group name={"kid"} ref={(value: NodeId3D): void => { kids.push(value); }} />
					</Node>
				) })}
				{Show({ when: accessor(() => on()), children: element(<Node id={loose} />) })}
			</Group>
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const handle = only(refs);
	const scene = handle.scene;
	assert namesUnder(scene, scene.root) === "sg", namesUnder(scene, scene.root);
	assert namesUnder(scene, groups[0].index) === "kl", namesUnder(scene, groups[0].index);
	assert namesUnder(scene, kept.index) === "kid";
	assert !scene.nodes[kept.index].flags.has(NodeFlag.Visible), "Node binds NodeProps onto the node it places";
	setOn(false); flush();
	assert scene.isLive(kept) && scene.isLive(loose), "Node does not free what it placed";
	assert !scene.isLive(kids[0]), "what Neon mounted under it is freed";
	assert namesUnder(scene, scene.root) === "ksg", namesUnder(scene, scene.root);
	assert namesUnder(scene, kept.index) === "";
	assert !drawn(scene, loose), "a node that came detached goes back out of the drawn tree";
	setOn(true); flush();
	assert namesUnder(scene, groups[0].index) === "kl" && namesUnder(scene, kept.index) === "kid";
	const removed = remove(scene, kept);
	setShown(true); flush();
	setOn(false); flush();
	assert !scene.isLive(kept) && scene.isLive(loose), "a node the app freed is skipped, never written";
	dispose();
	assert scene.closed;
}
