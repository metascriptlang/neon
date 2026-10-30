// RenderTexture children: a Scene2D draws into the texture; View and Text are refused, never mounted into the outer UI.
//   msc run tests/device/renderTextureChildren.ms
// Exits 0 when every case holds.

import { createRoot } from "../../src/core/owner";
import { resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { MockNode, mockNode, mockHost, mockToString } from "../../src/render/host";
import { Void, View, Text } from "../../src/components/primitives";
import { Scene2D, Rect } from "../../src/components/scene2d";
import { Scene3D, RenderTexture } from "../../src/components/scene3d";
import { rgba } from "../../../void/src/void2d/types";
import { setup2d } from "../../../void/src/void2d/draw";
import { gfxSetup } from "../../../void/src/host/gpu";

@include("../../../void/src/host/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function mounted(app: () => NeonNode): string {
	let message = "";
	const root: MockNode = mockNode("root");
	createRoot((dispose: () => void): void => {
		try {
			app()(mockHost(), root as unknown as HostNode, null);
			message = "mounted: " + mockToString(root);
		} catch (error) { message = error.toString(); } finally { dispose(); resetErrorHalt(); }
	});
	return message;
}

function expect(what: string, actual: string, wanted: string): void {
	if (!actual.includes(wanted)) {
		console.log("FAIL RenderTexture children:", what, actual);
		process.exit(1);
	}
}

function init(): void {
	gfxSetup();
	setup2d();
	expect("a Scene2D mounts into the texture and leaves the outer UI empty",
		mounted((): NeonNode => element(<Void><Scene3D><RenderTexture width={8} height={8}><Scene2D><Rect width={4.0} height={4.0} color={rgba(1.0, 0.0, 0.0, 1.0)} /></Scene2D></RenderTexture></Scene3D></Void>)),
		"<voidroot></voidroot></void></root>");
	expect("a styled View is refused", mounted((): NeonNode => element(<Void><Scene3D><RenderTexture width={8} height={8}><View style={{ width: 4 }} /></RenderTexture></Scene3D></Void>)),
		"belongs in <Void>, <Texture> or a 2D parent");
	expect("a Text is refused", mounted((): NeonNode => element(<Void><Scene3D><RenderTexture width={8} height={8}><Text>hi</Text></RenderTexture></Scene3D></Void>)),
		"has no 3D node");
	console.log("PASS RenderTexture children: Scene2D into the texture, View and Text refused");
	process.exit(0);
}

voidRun(64, 64, init, (): void => {});
