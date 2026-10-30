// Text3D in a window's Void takes the window's font, on the GPU.
//   msc build tests/device/text3dFont.ms --output=out/text3dFont && out/text3dFont   (from the Neon checkout, beside ../void)
// Exits 0 once a label without textStyle is shaped in the window font.

import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Text3D } from "../../src/components/scene3d";
import { AreaWindow, WindowArea, windowHost, windowNode } from "../../src/platform/void/windowHost";
import { FontId, DEFAULT_FONT, addFont } from "../../../void/src/void2d/font";
import { labelTexts } from "../../../void/src/void2d/labelText";
import { setup2d, preparePipelines } from "../../../void/src/void2d/draw";
import { BlendMode } from "../../../void/src/gpu/state";
import { gfxSetup } from "../../../void/src/host/gpu";

@include("../../../void/src/host/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const FONT_PATH = "../void/assets/font.ttf";
let font: FontId = DEFAULT_FONT;

function fail(message: string): void {
	console.log("FAIL Text3D font device:", message);
	process.exit(1);
}

function fontOf(text: string): FontId {
	for (const entry of labelTexts) {
		if (entry.text === text) { return entry.style.font; }
	}
	fail("no label shaped \"" + text + "\"");
	return DEFAULT_FONT;
}

function init(): void {
	gfxSetup();
	setup2d();
	preparePipelines([BlendMode.Alpha]);
	const loaded = addFont(FONT_PATH);
	if (!loaded.ok) { fail("the test font did not load from " + FONT_PATH); return; }
	font = loaded.value;
	const window: AreaWindow = {
		name: "text3d font window",
		font: font,
		family: null,
		pixelWidth: (): int32 => 320 as int32,
		pixelHeight: (): int32 => 240 as int32,
		requestFrame: (): void => {},
		dirty: (): void => {},
		setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => {},
		opened: (area: WindowArea): void => {},
		released: (area: WindowArea): void => {},
	};
	render(element(<Void><Scene3D>
		<Text3D text="window font" />
	</Scene3D></Void>), windowHost(window), windowNode("window"));
}

function frame(): void {
	const shaped = fontOf("window font");
	if (shaped !== font) { fail("a Text3D without textStyle shaped in font " + (shaped as int32).toString() + ", not the window's " + (font as int32).toString()); }
	console.log("PASS Text3D font device: the label takes the window font");
	process.exit(0);
}

voidRun(320, 240, init, frame);
