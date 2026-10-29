import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Host, HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { NeonNode } from "../../src/render/hostTypes";
import { Void } from "../../src/components/primitives";
import { Scene3DHandle } from "../../src/components/scene3d/core";
import { Scene3D } from "../../src/components/scene3d/scene";
import {
	createMaterial, DistanceFade, Flipbook, MaterialProps,
} from "../../src/components/scene3d/material";
import { DrawContext, MaterialId } from "../../../void/src/void3d/draw";
import { MaterialKind } from "../../../void/src/void3d/material";
import { TextureId } from "../../../void/src/void3d/texture";
import { Texture } from "../../../void/src/gpu/texture";
import {
	MOVING_FLIPBOOK_COLUMNS, MOVING_FLIPBOOK_ROWS, MOVING_FLIPBOOK_FRAMES, MOVING_FLIPBOOK_SPEED,
	MOVING_FLIPBOOK_START_TIME, MOVING_FLIPBOOK_START_FRAME, MOVING_FLIPBOOK_LOOP,
	MOVING_FLIPBOOK_BLEND, MOVING_FADE_NEAR_START, MOVING_FADE_NEAR_END, MOVING_FADE_FAR_START,
	MOVING_FADE_FAR_END, MOVING_COLOR_KEY, movingBase,
} from "../../../void/src/void3d/gpu3d";
import { Color, rgba } from "../../../void/src/void2d/types";
import { addedOwner } from "../../../void/src/test/drawHelpers";

function fixed(context: DrawContext): Accessor<TextureId> {
	const id = addedOwner(context, Texture.adopt(0, 77, 1, 1));
	return accessor((): TextureId => id);
}

function uniformAt(context: DrawContext, material: MaterialId, at: int32): float32 {
	const block = context.materials[material.index].uniforms;
	return context.uniforms.values[block.offset + at];
}

function sheet(frames: int32): Flipbook {
	return {
		columns: 4, rows: 2, numberOfFrames: frames, fps: 12.0, startFrame: 1, startTime: 0.5,
		loop: true, blend: false,
	};
}

function mounted(
	build: (context: DrawContext) => MaterialProps,
): [Scene3DHandle, Accessor<MaterialId>[], () => void] {
	const refs: Scene3DHandle[] = [];
	const made: Accessor<MaterialId>[] = [];
	let props: MaterialProps = {};
	const painted: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		made.push(createMaterial(props));
	};
	const dispose = render(element(<Void>
		<Scene3D ref={(handle: Scene3DHandle): void => {
			refs.push(handle);
			props = build(handle.context);
		}}>{painted}</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	return [refs[0], made, dispose];
}

function refusal(build: (context: DrawContext) => MaterialProps): string {
	let message = "";
	try {
		const [handle, made, dispose] = mounted(build);
		dispose();
	} catch (error) { message = error.message; }
	finally { resetErrorHalt(); }
	return message;
}

test "createMaterial flipbook writes Void's moving block on a UV-transform key and follows its signal" {
	const [book, setBook] = createSignal<Flipbook>(sheet(8));
	const [handle, made, dispose] = mounted((context: DrawContext): MaterialProps => ({
		texture: fixed(context),
		flipbook: accessor((): Flipbook => book()),
	}));
	try {
		const context = handle.context;
		const material = made[0]();
		const key = context.materials[material.index].program;
		assert key.uvTransform && !key.pbr;
		const base = movingBase(key);
		assert uniformAt(context, material, base + MOVING_FLIPBOOK_COLUMNS) === 4.0;
		assert uniformAt(context, material, base + MOVING_FLIPBOOK_ROWS) === 2.0;
		assert uniformAt(context, material, base + MOVING_FLIPBOOK_FRAMES) === 8.0;
		assert uniformAt(context, material, base + MOVING_FLIPBOOK_SPEED) === 12.0;
		assert uniformAt(context, material, base + MOVING_FLIPBOOK_START_TIME) === 0.5;
		assert uniformAt(context, material, base + MOVING_FLIPBOOK_START_FRAME) === 1.0;
		assert uniformAt(context, material, base + MOVING_FLIPBOOK_LOOP) === 1.0;
		assert uniformAt(context, material, base + MOVING_FLIPBOOK_BLEND) === 0.0;
		setBook({ ...sheet(6), loop: false, blend: true }); flush();
		assert made[0]() === material, "a flipbook change keeps the material";
		assert uniformAt(context, material, base + MOVING_FLIPBOOK_FRAMES) === 6.0;
		assert uniformAt(context, material, base + MOVING_FLIPBOOK_LOOP) === 0.0;
		assert uniformAt(context, material, base + MOVING_FLIPBOOK_BLEND) === 1.0;
	} finally { dispose(); resetErrorHalt(); }
}

test "createMaterial flipbook works on an unlit program too" {
	const [handle, made, dispose] = mounted((context: DrawContext): MaterialProps => ({
		unlit: accessor((): boolean => true),
		texture: fixed(context),
		flipbook: accessor((): Flipbook => sheet(8)),
	}));
	try {
		const context = handle.context;
		const material = made[0]();
		const base = movingBase(context.materials[material.index].program);
		assert uniformAt(context, material, base + MOVING_FLIPBOOK_FRAMES) === 8.0;
	} finally { dispose(); resetErrorHalt(); }
}

test "createMaterial flipbook names what Void cannot play" {
	const bare = refusal((context: DrawContext): MaterialProps => ({
		flipbook: accessor((): Flipbook => sheet(8)),
	}));
	assert bare.includes("createMaterial: flipbook, distanceFade and colorKey need a texture"), bare;
	const pbr = refusal((context: DrawContext): MaterialProps => ({
		texture: fixed(context),
		roughness: accessor((): float32 => 0.5),
		flipbook: accessor((): Flipbook => sheet(8)),
	}));
	assert pbr.includes("createMaterial: flipbook, distanceFade and colorKey need a program without pbr"), pbr;
	const many = refusal((context: DrawContext): MaterialProps => ({
		texture: fixed(context),
		flipbook: accessor((): Flipbook => sheet(9)),
	}));
	assert many.includes("createMaterial: flipbook numberOfFrames"), many;
	const none = refusal((context: DrawContext): MaterialProps => ({
		texture: fixed(context),
		flipbook: accessor((): Flipbook => sheet(0)),
	}));
	assert none.includes("createMaterial: flipbook numberOfFrames"), none;
	const past = refusal((context: DrawContext): MaterialProps => ({
		texture: fixed(context),
		flipbook: accessor((): Flipbook => ({ ...sheet(8), startFrame: 8 })),
	}));
	assert past.includes("createMaterial: flipbook startFrame"), past;
	const flat = refusal((context: DrawContext): MaterialProps => ({
		texture: fixed(context),
		flipbook: accessor((): Flipbook => ({ ...sheet(8), columns: 0 })),
	}));
	assert flat.includes("createMaterial: flipbook columns and rows"), flat;
	const slow = refusal((context: DrawContext): MaterialProps => ({
		texture: fixed(context),
		flipbook: accessor((): Flipbook => ({ ...sheet(8), fps: -1.0 })),
	}));
	assert slow.includes("createMaterial: flipbook fps"), slow;
}

test "createMaterial distanceFade writes the four distances on a blended material" {
	const [handle, made, dispose] = mounted((context: DrawContext): MaterialProps => ({
		texture: fixed(context),
		kind: accessor((): MaterialKind => MaterialKind.Alpha),
		distanceFade: accessor((): DistanceFade => ({
			nearStart: 1.0, nearEnd: 2.0, farStart: 10.0, farEnd: 20.0,
		})),
	}));
	try {
		const context = handle.context;
		const material = made[0]();
		const key = context.materials[material.index].program;
		assert key.uvTransform;
		const base = movingBase(key);
		assert uniformAt(context, material, base + MOVING_FADE_NEAR_START) === 1.0;
		assert uniformAt(context, material, base + MOVING_FADE_NEAR_END) === 2.0;
		assert uniformAt(context, material, base + MOVING_FADE_FAR_START) === 10.0;
		assert uniformAt(context, material, base + MOVING_FADE_FAR_END) === 20.0;
	} finally { dispose(); resetErrorHalt(); }
}

test "createMaterial distanceFade refuses an opaque or cut material and an end before its start" {
	const fade = (nearEnd: float32): DistanceFade => ({
		nearStart: 1.0, nearEnd: nearEnd, farStart: 0.0, farEnd: 0.0,
	});
	const opaque = refusal((context: DrawContext): MaterialProps => ({
		texture: fixed(context),
		distanceFade: accessor((): DistanceFade => fade(2.0)),
	}));
	assert opaque.includes("createMaterial: distanceFade shows only through blending"), opaque;
	const cut = refusal((context: DrawContext): MaterialProps => ({
		texture: fixed(context),
		kind: accessor((): MaterialKind => MaterialKind.AlphaKill),
		distanceFade: accessor((): DistanceFade => fade(2.0)),
	}));
	assert cut.includes("createMaterial: distanceFade shows only through blending"), cut;
	const backwards = refusal((context: DrawContext): MaterialProps => ({
		texture: fixed(context),
		kind: accessor((): MaterialKind => MaterialKind.Alpha),
		distanceFade: accessor((): DistanceFade => fade(0.5)),
	}));
	assert backwards.includes("createMaterial: distanceFade needs each end at or past its start"), backwards;
}

test "createMaterial colorKey writes MOVING_COLOR_KEY and refuses alpha 0" {
	const [handle, made, dispose] = mounted((context: DrawContext): MaterialProps => ({
		texture: fixed(context),
		colorKey: accessor((): Color => rgba(1.0, 0.0, 0.5, 1.0)),
	}));
	try {
		const context = handle.context;
		const material = made[0]();
		const base = movingBase(context.materials[material.index].program);
		assert uniformAt(context, material, base + MOVING_COLOR_KEY) === 1.0;
		assert uniformAt(context, material, base + MOVING_COLOR_KEY + 1) === 0.0;
		assert uniformAt(context, material, base + MOVING_COLOR_KEY + 2) === 0.5;
		assert uniformAt(context, material, base + MOVING_COLOR_KEY + 3) === 1.0;
	} finally { dispose(); resetErrorHalt(); }
	const clear = refusal((context: DrawContext): MaterialProps => ({
		texture: fixed(context),
		colorKey: accessor((): Color => rgba(1.0, 0.0, 0.5, 0.0)),
	}));
	assert clear.includes("createMaterial: colorKey needs a finite colour with alpha above 0"), clear;
}
