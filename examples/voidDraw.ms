// A full-window <Void> drawn by hand through its ref: a directive factory takes the
// area handle, writes one void2d label, and logs the raw input the handle forwards.
//   msc build examples/voidDraw.ms --output=out/voidDraw.exe
//   out/voidDraw.exe              (run from the neon checkout: the font path is relative)

import { element } from "../src/macros/ui/element";
import { NeonNode } from "../src/render/node";
import { VoidAreaHandle, AreaKeyEvent, AreaKeyAction, AreaPointerEvent, AreaPointerKind, AreaPreedit, AreaResize } from "../src/render/voidAreaHandle";
import { Void } from "../src/components/primitives";
import { runWindow, DesktopOptions, desktopOptions, areaScene } from "../src/platform/ion/window";
import { label as newLabel, setText, setPosition, setFont } from "../../void/src/void2d/node";
import { add } from "../../void/src/void2d/scene";
import { rgba } from "../../void/src/void2d/types";
import { addFont } from "../../void/src/void2d/font";
import { exit } from "std/process";

function caption(width: int32, height: int32, scale: float32): string {
	return `drawn by hand: ${width}x${height} at ${scale}x`;
}

function drawing(): (area: VoidAreaHandle) => void {
	return (area: VoidAreaHandle): void => {
		console.log(`area size ${area.pixelWidth()}x${area.pixelHeight()} scale ${area.scale()}`);
		const scene = areaScene(area);
		const label = scene.newLabel(caption(area.pixelWidth(), area.pixelHeight(), area.scale()), 20.0, rgba(0.8, 0.84, 0.96, 1.0));
		const font = addFont("../void/assets/font.ttf");
		if (!font.ok) {
			console.log("voidDraw: the font ../void/assets/font.ttf did not load");
			exit(3);
		}
		label.setFont(font.value);
		scene.add(label.setPosition(24.0, 24.0));
		area.onResize((e: AreaResize): void => {
			console.log(`resize ${e.pixelWidth}x${e.pixelHeight} scale ${e.scale}`);
			label.setText(caption(e.pixelWidth, e.pixelHeight, e.scale));
			area.requestFrame();
		});
		area.onKey((e: AreaKeyEvent): void => {
			const action = e.action === AreaKeyAction.Release ? "release" : e.action === AreaKeyAction.Repeat ? "repeat" : "press";
			console.log(`key ${action} scancode=${e.scancode} unshifted=${e.unshifted} text="${e.text}"`);
		});
		area.onText((text: string): void => { console.log(`text "${text}"`); });
		area.onPreedit((e: AreaPreedit): void => { console.log(`preedit "${e.text}" cursorUtf8Offset=${e.cursorUtf8Offset}`); });
		area.onPointer((e: AreaPointerEvent): void => {
			const kind = e.kind === AreaPointerKind.Button ? "button" : e.kind === AreaPointerKind.Wheel ? "wheel" : e.kind === AreaPointerKind.Leave ? "leave" : "motion";
			console.log(`pointer ${kind} px=${e.pixelX},${e.pixelY} button=${e.button} pressed=${e.pressed}`);
		});
		area.onFocus((focused: boolean): void => { console.log(`focus ${focused}`); });
		area.requestFrame();
	};
}

function App(): NeonNode {
	return element(<Void style={{ backgroundColor: "#1e1e2e" }} ref={drawing()} />);
}

const opts: DesktopOptions = { ...desktopOptions("Neon draws a Void", 640, 360), font: "../void/assets/font.ttf" };
exit(runWindow(opts, App));
