import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Graphics } from "../../src/components/scene2d";
import { GraphicsOp } from "../../src/render/graphics";
import { NodeRef, GraphicsMesh, graphics, dispose, isLive } from "../../../void/src/void2d/node";
import { tile, sub, flipX, flipY, premultiplied, vec2, rgba } from "../../../void/src/void2d/types";
import { fillTexRect, fillTexPolygon, fillCheckerRect } from "../../../void/src/void2d/graphics";
import { Texture, create, close } from "../../../void/src/gpu/texture";

function geometry(node: NodeRef): GraphicsMesh {
	return node.scene.meshes[node.scene.payloads[node.id.index]];
}

test "Graphics snapshots borrowed Tile UVs and replaces source without closing sibling owners" {
	const first = Texture.create(32, 16, null);
	const second = Texture.create(64, 32, null);
	const a = tile(first, 32.0, 16.0).sub(8.0, 4.0, 8.0, 4.0).flipX();
	const b = tile(second, 64.0, 32.0).sub(16.0, 8.0, 16.0, 8.0).flipY().premultiplied();
	const points = [vec2(1.0, 2.0), vec2(9.0, 2.0), vec2(5.0, 6.0),
		vec2(9.0, 10.0), vec2(1.0, 10.0)];
	const color = rgba(0.8, 0.6, 0.4, 0.7);
	const [replacement, setReplacement] = createSignal(false);
	const [empty, setEmpty] = createSignal(false);
	const read = (): GraphicsOp[] => {
		if (empty()) { return []; }
		const current = replacement() ? b : a;
		return [
			{ kind: "fillTexRect", tile: current, x: 2.0, y: 3.0, w: 8.0, h: 4.0, color: color },
			{ kind: "fillCheckerRect", x: 0.0, y: 0.0, w: 4.0, h: 4.0,
				a: color, b: rgba(0.0, 0.0, 0.0, 1.0), cell: 2.0 },
			{ kind: "fillTexPolygon", tile: current, points: points,
				originX: 1.0, originY: 2.0, tileW: 8.0, tileH: 4.0, color: color },
		];
	};
	const sibling: GraphicsOp[] = [
		{ kind: "fillTexRect", tile: a, x: 0.0, y: 0.0, w: 8.0, h: 4.0, color: color },
	];
	const nodes: NodeRef[] = [];
	try {
		for (let mount: int32 = 0; mount < 2; mount++) {
			const cleanup = render(element(<Void><Scene2D>
				<Graphics operations={read()} ref={(node: NodeRef): void => { nodes.push(node); }} />
				<Graphics operations={sibling} ref={(node: NodeRef): void => { nodes.push(node); }} />
			</Scene2D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
			const node = nodes[mount * 2];
			const control = node.scene.graphics();
			try {
				const id = node.id;
				assert geometry(node).source.texture === first;
				assert !geometry(node).alphaPremultiplied;
				setReplacement(true);
				control.fillTexRect(b, 2.0, 3.0, 8.0, 4.0, color);
				control.fillCheckerRect(0.0, 0.0, 4.0, 4.0, color, rgba(0.0, 0.0, 0.0, 1.0), 2.0);
				control.fillTexPolygon(b, points, 1.0, 2.0, 8.0, 4.0, color);
				const actual = geometry(node);
				const expected = geometry(control);
				assert actual.source.texture === second && actual.alphaPremultiplied;
				assert actual.mesh.length === expected.mesh.length && actual.mesh.length > 0;
				assert actual.records.length === expected.records.length;
				for (let j: int32 = 0; j < actual.mesh.length; j++) {
					assert actual.mesh[j] === expected.mesh[j];
				}
				for (let j: int32 = 0; j < actual.records.length; j++) {
					assert actual.records[j] === expected.records[j];
				}
				assert geometry(nodes[mount * 2 + 1]).source.texture === first;
				assert node.id === id && nodes.length === (mount + 1) * 2;
				setEmpty(true);
				assert geometry(node).mesh.length === 0 && geometry(node).records.length === 0;
				assert geometry(node).source.texture === null && !geometry(node).alphaPremultiplied;
			} finally { control.dispose(); cleanup(); }
			setReplacement(false); setEmpty(false);
			assert !node.isLive() && !nodes[mount * 2 + 1].isLive();
			assert !first.closed && !second.closed && first.view === 0 && second.view === 0;
		}
	} finally { first.close(); second.close(); }
	assert first.closed && second.closed;
}

test "Graphics refuses incompatible shared mesh sources and alpha before replacing geometry" {
	const first = Texture.create(8, 8, null);
	const second = Texture.create(8, 8, null);
	const a = tile(first, 8.0, 8.0);
	const b = tile(second, 8.0, 8.0);
	const color = rgba(1.0, 1.0, 1.0, 1.0);
	const initial: GraphicsOp[] = [
		{ kind: "fillTexRect", tile: a, x: 4.0, y: 5.0, w: 8.0, h: 8.0, color: color },
	];
	const [value, setValue] = createSignal<GraphicsOp[]>(initial);
	const nodes: NodeRef[] = [];
	const cleanup = render(element(<Void><Scene2D>
		<Graphics operations={value()} ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
	try {
		const incompatible: GraphicsOp[] = [
			{ kind: "fillTexRect", tile: b, x: 9.0, y: 5.0, w: 8.0, h: 8.0, color: color },
			{ kind: "fillTexRect", tile: a.premultiplied(), x: 9.0, y: 5.0,
				w: 8.0, h: 8.0, color: color },
			{ kind: "fillRect", x: 9.0, y: 5.0, w: 8.0, h: 8.0, color: color },
		];
		for (const op of incompatible) {
			let message = "";
			try { setValue([initial[0], op]); } catch (error) { message = error.message; }
			assert message === "Graphics: mesh operations must share one TextureSource and alphaPremultiplied value";
			assert geometry(nodes[0]).mesh.length === 48 && geometry(nodes[0]).mesh[0] === 4.0;
			assert geometry(nodes[0]).source.texture === first && !first.closed && !second.closed;
		}
	} finally { cleanup(); first.close(); second.close(); }
}
