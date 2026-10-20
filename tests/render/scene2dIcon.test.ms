import { Accessor, createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Errored, Show } from "../../src/macros/ui/flow";
import { Host, NeonNode } from "../../src/render/hostTypes";
import { HostNode, mockHost, mockNode, render } from "../../src/render/host";
import { Void, View } from "../../src/components/primitives";
import { Scene2D, Icon, Rect } from "../../src/components/scene2d";
import { NodeRef, DrawKind, kind, content, paint, order, isLive } from "../../../void/src/void2d/node";
import { IconId, registerIcon, iconHolds, iconOf } from "../../../void/src/void2d/icon";
import { svgMaskCompiled } from "../../../void/src/void2d/svgMask";
import { rgba } from "../../../void/src/void2d/types";
import { isDirty, paint as paintScene } from "../../../void/src/void2d/scene";
import { clearChanges } from "../../../void/src/void2d/node";
import { frameEnd } from "../../../void/src/void2d/draw";

function unusedId(): IconId { throw new Error("disabled Icon must not read its id"); }

test "Icon without the SVG module refuses by name before reading its id" {
	when (voidSvg) {
		assert svgMaskCompiled();
	} else {
		let message = "";
		createRoot((dispose: () => void): void => {
			try {
				const root = mockNode("root");
				element(<Void><Scene2D><Icon id={unusedId()} width={16.0} height={16.0} color={rgba(1.0, 1.0, 1.0, 1.0)} /></Scene2D></Void>)(mockHost(), root as unknown as HostNode, null);
			} catch (error) { message = error.toString(); }
			finally { dispose(); resetErrorHalt(); }
		});
		assert message.includes("Icon: requires -d:voidSvg"), message;
		assert !svgMaskCompiled();
	}
}

when (voidSvg) {
	function registered(width: int32): IconId {
		const source = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="16" viewBox="0 0 ${width} 16"><rect width="${width}" height="16" fill="#000"/></svg>`;
		const result = registerIcon(source);
		if (!result.ok) { throw new Error("Icon fixture: " + result.error.what); }
		return result.value;
	}

	test "Icon replaces its id in place and transfers only its own holds" {
		const first = registered(16);
		const second = registered(24);
		const [id, setId] = createSignal<IconId>(first);
		const nodes: NodeRef[] = [];
		const root = mockNode("root");
		const dispose = render(element(<Void><Scene2D>
			<Icon id={id()} width={20.0} height={12.0} color={rgba(0.5, 0.25, 0.75, 1.0)} order={{ zIndex: 7, visible: true, name: "kept icon", noOverlap: true }}
				ref={(node: NodeRef): void => { nodes.push(node); }}>
				<Rect width={2.0} height={2.0} color={rgba(1.0, 0.0, 0.0, 1.0)} />
			</Icon>
			<Icon id={first} width={8.0} height={8.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
				ref={(node: NodeRef): void => { nodes.push(node); }} />
		</Scene2D></Void>), mockHost(), root as unknown as HostNode);
		try {
			const node = nodes[0];
			const slot = node.scene.payloads[node.id.index];
			assert node.kind() === DrawKind.Icon && iconOf(slot) === first;
			assert iconHolds(first) === 2 && iconHolds(second) === 0;
			setId(second); flush();
			assert nodes.length === 2 && nodes[0] === node && node.scene.payloads[node.id.index] === slot;
			assert iconOf(slot) === second && iconOf(nodes[1].scene.payloads[nodes[1].id.index]) === first;
			assert iconHolds(first) === 1 && iconHolds(second) === 1;
			assert node.content().w === 20.0 && node.content().h === 12.0 && node.paint().color.b === 0.75;
			assert node.order().zIndex === 7 && node.order().visible && node.order().name === "kept icon";
			assert node.order().noOverlap && node.scene.children[node.id.index].length === 1;
			setId(second); flush();
			assert iconHolds(first) === 1 && iconHolds(second) === 1;
		} finally { dispose(); }
		assert iconHolds(first) === 0 && iconHolds(second) === 0 && !nodes[0].isLive();
	}

	test "Icon size and tint updates retain identity and wake only the owning area" {
		const id = registered(16);
		const [size, setSize] = createSignal<float32>(10.0);
		const [tint, setTint] = createSignal<float32>(0.2);
		const nodes: NodeRef[] = [];
		const siblingNodes: NodeRef[] = [];
		const root = mockNode("root");
		const dispose = render(element(<View>
			<Void><Scene2D><Icon id={id} width={size()} height={size() + 2.0} color={rgba(tint(), 0.3, 0.4, 1.0)}
				ref={(node: NodeRef): void => { nodes.push(node); }} /></Scene2D></Void>
			<Void><Scene2D><Icon id={id} width={8.0} height={8.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
				ref={(node: NodeRef): void => { siblingNodes.push(node); }} /></Scene2D></Void>
		</View>), mockHost(), root as unknown as HostNode);
		const first = root.children[0].children[0];
		const sibling = root.children[0].children[1];
		try {
			for (const node of [nodes[0], siblingNodes[0]]) {
				node.scene.paintScene(320.0, 240.0, 1.0);
				frameEnd();
				node.scene.clearChanges();
				assert !node.scene.isDirty();
			}
			const requests = first.attrs.length;
			const siblingRequests = sibling.attrs.length;
			setSize(30.0); setTint(0.8); flush();
			assert nodes.length === 1 && nodes[0].content().w === 30.0 && nodes[0].content().h === 32.0;
			assert nodes[0].paint().color.r === 0.8;
			assert first.attrs.length > requests && sibling.attrs.length === siblingRequests,
				"first " + requests.toString() + "->" + first.attrs.length.toString() +
				", sibling " + siblingRequests.toString() + "->" + sibling.attrs.length.toString() +
				", dirty=" + nodes[0].scene.isDirty().toString();
			assert !siblingNodes[0].scene.isDirty();
			assert iconHolds(id) === 2;
		} finally { dispose(); }
		const requests = first.attrs.length;
		setSize(5.0); setTint(0.5); flush();
		assert first.attrs.length === requests && iconHolds(id) === 0 && !nodes[0].isLive();
	}

	test "Icon hide and remount release old holds and acquire one fresh placement" {
		const first = registered(16);
		const second = registered(24);
		const [shown, setShown] = createSignal(true);
		const [id, setId] = createSignal<IconId>(first);
		const nodes: NodeRef[] = [];
		const root = mockNode("root");
		const dispose = render(element(<Void><Scene2D><Show when={shown()}>
			<Icon id={id()} width={16.0} height={16.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
				ref={(node: NodeRef): void => { nodes.push(node); }} />
		</Show></Scene2D></Void>), mockHost(), root as unknown as HostNode);
		try {
			assert iconHolds(first) === 1;
			setShown(false); flush();
			assert !nodes[0].isLive() && iconHolds(first) === 0;
			setId(second); flush();
			assert iconHolds(second) === 0;
			setShown(true); flush();
			assert nodes.length === 2 && nodes[1].isLive() && iconHolds(second) === 1;
		} finally { dispose(); }
		assert iconHolds(first) === 0 && iconHolds(second) === 0;
	}

	test "Icon rejects invalid initial size before acquiring a placement" {
		const id = registered(16);
		const nodes: NodeRef[] = [];
		let message = "";
		createRoot((dispose: () => void): void => {
			try {
				const root = mockNode("root");
				element(<Void><Scene2D><Icon id={id} width={-1.0} height={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
					ref={(node: NodeRef): void => { nodes.push(node); }} /></Scene2D></Void>)(mockHost(), root as unknown as HostNode, null);
			} catch (error) {
				message = error.toString();
				assert iconHolds(id) === 0 && nodes.length === 0;
			} finally { dispose(); resetErrorHalt(); }
		});
		assert message.includes("Icon: width and height must be finite and nonnegative"), message;
		assert iconHolds(id) === 0;
	}

	test "Icon rejected size preserves the pair and Errored reset retains its node" {
		const id = registered(16);
		const [width, setWidth] = createSignal<float32>(10.0);
		const [height, setHeight] = createSignal<float32>(12.0);
		const nodes: NodeRef[] = [];
		const errors: Error[] = [];
		const resets: (() => void)[] = [];
		const root = mockNode("root");
		const dispose = render(element(<Void>{Errored({
			children: element(<Scene2D><Icon id={id} width={width()} height={height()} color={rgba(1.0, 1.0, 1.0, 1.0)}
				ref={(node: NodeRef): void => { nodes.push(node); }} /></Scene2D>),
			fallback: (error: Accessor<Error>, reset: () => void): NeonNode => {
				errors.push(error()); resets.push(reset); return element(<View />);
			},
		})}</Void>), mockHost(), root as unknown as HostNode);
		try {
			const node = nodes[0];
			setWidth(-1.0); setHeight(6.0); flush();
			assert errors.length === 1 && errors[0].toString().includes("Icon: width and height must be finite and nonnegative");
			assert nodes.length === 1 && node.isLive() && iconHolds(id) === 1;
			assert node.content().w === 10.0 && node.content().h === 12.0;
			setWidth(0.0); setHeight(0.0); resets[0](); flush();
			assert errors.length === 1 && nodes.length === 1 && nodes[0] === node && node.isLive();
			assert node.content().w === 0.0 && node.content().h === 0.0 && iconHolds(id) === 1;
		} finally { dispose(); resetErrorHalt(); }
		assert !nodes[0].isLive() && iconHolds(id) === 0;
	}

	test "Icon throwing ref or child releases placement before the caller disposes" {
		for (const childFails of [false, true]) {
			const id = registered(16);
			const nodes: NodeRef[] = [];
			let message = "";
			const throwing: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
				throw new Error("Icon child failure");
			};
			createRoot((dispose: () => void): void => {
				try {
					const root = mockNode("root");
					element(<Void><Scene2D><Icon id={id} width={16.0} height={16.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
						ref={(node: NodeRef): void => {
							nodes.push(node);
							if (!childFails) { throw new Error("Icon ref failure"); }
						}}>{childFails ? throwing : null}</Icon></Scene2D></Void>)(mockHost(), root as unknown as HostNode, null);
				} catch (error) {
					message = error.toString();
					assert nodes.length === 1 && !nodes[0].isLive() && iconHolds(id) === 0;
				} finally { dispose(); resetErrorHalt(); }
			});
			assert message.includes(childFails ? "Icon child failure" : "Icon ref failure"), message;
			assert iconHolds(id) === 0;
		}
	}
}
