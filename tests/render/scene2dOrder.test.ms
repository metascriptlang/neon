import { createSignal, Accessor, accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { For, Show } from "../../src/macros/ui/flow";
import { Host, HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { NeonNode } from "../../src/render/node";
import { Void, View, Text, TextInput, TextInputHandle, ViewHandle } from "../../src/components/primitives";
import { Scene2D, Group, Rect } from "../../src/components/scene2d";
import { NodeRef, Scene2D as VoidScene2D, refOf, getChildAt, getChildIndex } from "../../../void/src/void2d/node";
import { VoidNode, layoutPass } from "../../src/platform/void/host";
import { local, content, isLive } from "../../../void/src/void2d/node";
import { rgba } from "../../../void/src/void2d/types";

test "For reorders raw Scene2D nodes without remounting their owners" {
	const roots: NodeRef[] = [];
	const nodes: NodeRef[] = [];
	const [items, setItems] = createSignal<number[]>([1, 2, 3]);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D
		ref={(scene: VoidScene2D): void => { roots.push(scene.refOf(scene.root).getChildAt(0)); }}>
		{For<number>({ each: accessor(() => items()), usesIndex: false,
			children: (item: number, index: Accessor<number>): NeonNode => element(
				<Rect width={2.0} height={3.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
					ref={(node: NodeRef): void => { nodes.push(node); }} />
			) })}
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const parent = roots[0];
	try {
		assert nodes.length === 3;
		setItems([3, 1, 2]);
		assert nodes.length === 3;
		const third = parent.getChildIndex(nodes[2]);
		const first = parent.getChildIndex(nodes[0]);
		const second = parent.getChildIndex(nodes[1]);
		assert third >= 0 && third < first && first < second;
	} finally { dispose(); }
	setItems([2, 3]);
	assert !nodes[0].isLive() && !nodes[1].isLive() && !nodes[2].isLive() && parent.scene.closed;
}

test "For inserts a raw node before its existing sibling inside a Group" {
	const groups: NodeRef[] = [];
	const nodes: NodeRef[] = [];
	const [items, setItems] = createSignal<number[]>([1, 2]);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D><Group
		ref={(node: NodeRef): void => { groups.push(node); }}>
		{For<number>({ each: accessor(() => items()), usesIndex: false,
			children: (item: number, index: Accessor<number>): NeonNode => element(
				<Rect width={2.0} height={3.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
					ref={(node: NodeRef): void => { nodes.push(node); }} />
			) })}
	</Group></Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const parent = groups[0];
	try {
		setItems([1, 3, 2]);
		assert nodes.length === 3;
		const first = parent.getChildIndex(nodes[0]);
		const inserted = parent.getChildIndex(nodes[2]);
		const second = parent.getChildIndex(nodes[1]);
		assert first >= 0 && first < inserted && inserted < second;
	} finally { dispose(); }
	assert !parent.isLive() && parent.scene.closed;
}


test "Show owns effects while the host removes raw subtrees exactly once" {
	const nodes: NodeRef[] = [];
	const [shown, setShown] = createSignal(true);
	const dispose = render(element(<Void><Scene2D>
		{Show({ when: accessor(() => shown()), children: element(
			<Group ref={(node: NodeRef): void => { nodes.push(node); }}>
				<Rect width={2.0} height={3.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
					ref={(node: NodeRef): void => { nodes.push(node); }} />
			</Group>
		) })}
	</Scene2D></Void>), mockHost(), mockNode("root"));
	assert nodes.length === 2;
	setShown(false);
	assert !nodes[0].isLive() && !nodes[1].isLive();
	setShown(true);
	assert nodes.length === 4 && nodes[2].isLive() && nodes[3].isLive();
	assert nodes[0].id !== nodes[2].id;
	setShown(false);
	assert !nodes[2].isLive() && !nodes[3].isLive();
	dispose();
	assert nodes[0].scene.closed;
}

test "Scene2D UI and raw children share actual VoidNode parent and layout contract" {
	const parents: VoidNode[] = [];
	const views: VoidNode[] = [];
	const fields: VoidNode[] = [];
	const raw: NodeRef[] = [];
	const capture: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		parents.push(parent as VoidNode);
	};
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D><Group width={120.0} height={80.0}>
		{capture}
		<View style={{ width: 40, height: 20 }}
			ref={(handle: ViewHandle): void => { views.push(handle.node as VoidNode); }}>
			<Text>UI</Text>
			<TextInput value={"field"}
				ref={(handle: TextInputHandle): void => { fields.push(handle.node as VoidNode); }} />
		</View>
		<Rect width={2.0} height={3.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			ref={(node: NodeRef): void => { raw.push(node); }} />
	</Group></Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const parent = parents[0];
	const view = views[0];
	try {
		assert parent.raw && view.parent === parent && !view.raw;
		assert view.children.length === 2 && fields[0].parent === view;
		assert parent.ref.getChildIndex(view.ref) < parent.ref.getChildIndex(raw[0]);
		const box = parent.ref.content();
		layoutPass(view, box.w, box.h);
		assert view.ref.content().w === 40.0 && view.ref.content().h === 20.0;
	} finally { dispose(); }
	assert parent.disposed && view.disposed && fields[0].disposed;
	assert !raw[0].isLive() && parent.ref.scene.closed;
}

test "Scene2D releases root UI wrappers and original failure after partial child mount" {
	const views: VoidNode[] = [];
	const scenes: VoidScene2D[] = [];
	const nodes: NodeRef[] = [];
	const failed: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		element(<View ref={(handle: ViewHandle): void => { views.push(handle.node as VoidNode); }} />)(
			host, parent, before,
		);
		element(<Rect width={2.0} height={3.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			ref={(node: NodeRef): void => { nodes.push(node); }} />)(host, parent, before);
		throw new Error("original child failure");
	};
	const root = mockNode("root");
	let message = "";
	try {
		render(element(<Void><Scene2D
			ref={(scene: VoidScene2D): void => { scenes.push(scene); }}>
			{failed}
		</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	} catch (error) { message = error.message; }
	assert message === "original child failure";
	assert scenes[0].closed && !nodes[0].isLive();
	assert views[0].disposed && views[0].yg === null;
}

test "Scene2D keeps direct visible text, intrinsic and nested Void refusals" {
	const root = mockNode("root");
	const cases: NeonNode[] = [
		element(<Void><Scene2D>not a Label</Scene2D></Void>),
		element(<Void><Scene2D><div /></Scene2D></Void>),
		element(<Void><Scene2D><Void /></Scene2D></Void>),
	];
	for (const app of cases) {
		let message = "";
		try { render(app, mockHost(), root as unknown as HostNode); }
		catch (error) { message = error.message; }
		assert message.includes("Scene2D");
	}
}
