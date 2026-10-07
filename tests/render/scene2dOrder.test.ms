import { createSignal, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { For } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { NeonNode } from "../../src/render/node";
import { Void } from "../../src/components/primitives";
import { Scene2D, Group, Rect } from "../../src/components/scene2d";
import { NodeRef, Scene2D as VoidScene2D, refOf, getChildIndex } from "../../../void/src/void2d/node";
import { rgba } from "../../../void/src/void2d/types";

test "For reorders raw Scene2D nodes without remounting their owners" {
	const roots: NodeRef[] = [];
	const nodes: NodeRef[] = [];
	const [items, setItems] = createSignal<number[]>([1, 2, 3]);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D
		ref={(scene: VoidScene2D): void => { roots.push(scene.refOf(scene.root)); }}>
		{For<number>({ each: () => items(), usesIndex: false,
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
		{For<number>({ each: () => items(), usesIndex: false,
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
