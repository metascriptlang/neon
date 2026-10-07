import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Sprite, Group, Rect } from "../../src/components/scene2d";
import { NodeRef, isLive, content } from "../../../void/src/void2d/node";
import { getBounds } from "../../../void/src/void2d/render";
import {
	Tile, Bounds2D, emptyBounds, tile, whiteTile, sub, center, flipX, flipY, premultiplied,
	rgba,
} from "../../../void/src/void2d/types";
import { Texture, create, upload, close } from "../../../void/src/gpu/texture";

function deferredTexture(width: int32, height: int32, color: uint32): Texture {
	let pixels: Vec<uint32> = new Array(width * height);
	for (let i = 0; i < width * height; i++) { pixels[i] = color; }
	return Texture.create(width, height, (texture: Texture): void => {
		const uploaded = texture.upload(pixels);
		if (!uploaded.ok) { throw new Error("test texture upload refused"); }
	});
}

function hasBounds(this node: NodeRef, expected: Bounds2D): boolean {
	let result = emptyBounds();
	node.getBounds(result);
	return result === expected;
}

test "Sprite keeps atlas UVs, flipped offsets and alpha through borrowed Tile replacement" {
	const first = deferredTexture(64, 32, 0xFF0000FF as uint32);
	const second = deferredTexture(128, 64, 0xFFFF0000 as uint32);
	const initial = tile(first, 64.0, 32.0).sub(16.0, 8.0, 16.0, 8.0).center().flipX();
	const changed = tile(second, 128.0, 64.0).sub(32.0, 16.0, 8.0, 16.0)
		.flipX().flipY().premultiplied();
	const [replacement, setReplacement] = createSignal(false);
	const [width, setWidth] = createSignal<float32>(32.0);
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Sprite tile={replacement() ? changed : initial} width={width()}
			local={{ x: 40.0, y: 30.0, scaleX: 1.0, scaleY: 1.0,
				rotation: 0.0, pivotX: 0.0, pivotY: 0.0 }}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const node = nodes[0];
	const id = node.id;
	try {
		assert node.content().tile === initial;
		assert node.content().tile.source.texture === first;
		assert node.content().tile.u0 === 0.5 && node.content().tile.u1 === 0.25;
		assert node.content().w === 32.0 && node.content().h === 8.0;
		assert node.content().tile.dx === -8.0 && node.content().tile.dy === -4.0;
		setReplacement(true);
		assert node.content().tile === changed;
		assert node.content().tile.source.texture === second;
		assert node.content().tile.u0 === 0.3125 && node.content().tile.u1 === 0.25;
		assert node.content().tile.v0 === 0.5 && node.content().tile.v1 === 0.25;
		assert node.content().tile.alphaPremultiplied;
		assert node.content().w === 32.0 && node.content().h === 16.0;
		assert node.content().tile.dx === -8.0 && node.content().tile.dy === -16.0;
		setWidth(16.0);
		assert node.content().w === 16.0 && node.content().h === 16.0;
		let snapshot: Tile = node.content().tile;
		snapshot.u0 = 0.0; snapshot.dx = 0.0;
		assert node.content().tile === changed;
		setReplacement(false);
		assert node.content().tile === initial && !node.content().tile.alphaPremultiplied;
		assert node.content().w === 16.0 && node.content().h === 8.0;
		assert node.id === id && nodes.length === 1;
		assert !first.closed && !second.closed && first.view === 0 && second.view === 0;
	} finally {
		dispose();
		first.close(); second.close();
	}
	setReplacement(true); setWidth(48.0);
	assert !node.isLive() && node.scene.closed && first.closed && second.closed;
}

test "Sprite borrows deferred Texture owners across siblings, disposal and remount" {
	const first = deferredTexture(8, 4, 0xFFFFFFFF as uint32);
	const second = deferredTexture(16, 8, 0xFF000000 as uint32);
	const [replacement, setReplacement] = createSignal(false);
	const nodes: NodeRef[] = [];
	try {
		for (let mount = 0; mount < 2; mount++) {
			const root = mockNode("root");
			const dispose = render(element(<Void><Scene2D>
				<Sprite tile={tile(replacement() ? second : first,
					replacement() ? 16.0 : 8.0, replacement() ? 8.0 : 4.0)}
					ref={(node: NodeRef): void => { nodes.push(node); }} />
				<Sprite tile={tile(first, 8.0, 4.0)}
					ref={(node: NodeRef): void => { nodes.push(node); }} />
			</Scene2D></Void>), mockHost(), root as unknown as HostNode);
			const moving = nodes[mount * 2];
			const sibling = nodes[mount * 2 + 1];
			try {
				assert moving.content().tile.source.texture === first;
				setReplacement(true);
				assert moving.content().tile.source.texture === second;
				assert moving.content().w === 16.0 && moving.content().h === 8.0;
				assert sibling.content().tile.source.texture === first;
				assert sibling.content().w === 8.0 && sibling.content().h === 4.0;
				assert !first.closed && !second.closed;
			} finally { dispose(); }
			setReplacement(false);
			assert !moving.isLive() && !sibling.isLive() && moving.scene.closed;
			assert !first.closed && !second.closed;
			assert first.realloc !== null && second.realloc !== null;
		}
		assert nodes.length === 4 && first.view === 0 && second.view === 0;
	} finally { first.close(); second.close(); }
	assert first.closed && second.closed && first.realloc === null && second.realloc === null;
}

test "Sprite bounds answer its reactive atlas placement before a frame" {
	const initial = whiteTile(64.0, 32.0).sub(16.0, 8.0, 16.0, 8.0).center().flipX();
	const changed = whiteTile(128.0, 64.0).sub(32.0, 16.0, 8.0, 16.0).flipX().flipY();
	const [replacement, setReplacement] = createSignal(false);
	const [width, setWidth] = createSignal<float32>(32.0);
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Sprite tile={replacement() ? changed : initial} width={width()}
			local={{ x: 40.0, y: 30.0, scaleX: 1.0, scaleY: 1.0,
				rotation: 0.0, pivotX: 0.0, pivotY: 0.0 }}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		assert nodes[0].hasBounds({ xMin: 24.0, yMin: 26.0, xMax: 56.0, yMax: 34.0 });
		setReplacement(true);
		assert nodes[0].hasBounds({ xMin: 8.0, yMin: 14.0, xMax: 40.0, yMax: 30.0 });
		setWidth(16.0);
		assert nodes[0].hasBounds({ xMin: 24.0, yMin: 14.0, xMax: 40.0, yMax: 30.0 });
		setReplacement(false);
		assert nodes[0].hasBounds({ xMin: 32.0, yMin: 26.0, xMax: 48.0, yMax: 34.0 });
	} finally { dispose(); }
}

test "nested Rect bounds use reactive ancestors before a frame" {
	const [x, setX] = createSignal<float32>(10.0);
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Group local={{ x: x(), y: 20.0, scaleX: 1.0, scaleY: 1.0,
			rotation: 0.0, pivotX: 0.0, pivotY: 0.0 }}>
			<Rect width={4.0} height={6.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
				local={{ x: 5.0, y: 7.0, scaleX: 1.0, scaleY: 1.0,
					rotation: 0.0, pivotX: 0.0, pivotY: 0.0 }}
				ref={(node: NodeRef): void => { nodes.push(node); }} />
		</Group>
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		assert nodes[0].hasBounds({ xMin: 15.0, yMin: 27.0, xMax: 19.0, yMax: 33.0 });
		setX(30.0);
		assert nodes[0].hasBounds({ xMin: 35.0, yMin: 27.0, xMax: 39.0, yMax: 33.0 });
	} finally { dispose(); }
}
