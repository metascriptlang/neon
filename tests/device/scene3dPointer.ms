import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { NeonEvent } from "../../src/render/event";
import { AreaPointerKind } from "../../src/render/voidAreaHandle";
import { Void, View } from "../../src/components/primitives";
import { Scene3D, Mesh, Pointer3DEvent } from "../../src/components/scene3d";
import { AreaWindow, WindowArea, windowHost, windowNode, deliverPointer, deliverResize, drawArea } from "../../src/platform/void/windowHost";
import { MeshData, Rgba, addVertex, addTriangle } from "../../../void/src/void3d/meshData";
import { FontId, addFont } from "../../../void/src/void2d/font";
import { Vec3, vec3 } from "../../../void/src/math/math3d";
import { gfxSetup, fbWidth, fbHeight, dpiScale } from "../../../void/src/host/gpu";

@include("../../../void/src/host/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const areas: WindowArea[] = [];
const log: string[] = [];
let frames: int32 = 0;

function fail(message: string): void {
	console.log("FAIL Scene3D pointer device:", message);
	process.exit(1);
}

function square(): MeshData {
	let data: MeshData = MeshData.empty();
	const facing: Vec3 = vec3(0.0, 0.0, 1.0);
	const a: int32 = try addVertex(data, vec3(-1.0, -1.0, 0.0), facing, WHITE) catch 0;
	const b: int32 = try addVertex(data, vec3(1.0, -1.0, 0.0), facing, WHITE) catch 0;
	const c: int32 = try addVertex(data, vec3(1.0, 1.0, 0.0), facing, WHITE) catch 0;
	const d: int32 = try addVertex(data, vec3(-1.0, 1.0, 0.0), facing, WHITE) catch 0;
	const _t1: int32 = try addTriangle(data, a, b, c) catch 0;
	const _t2: int32 = try addTriangle(data, a, c, d) catch 0;
	return data;
}

function click(area: WindowArea, px: float64, py: float64): void {
	deliverPointer(area, { kind: AreaPointerKind.Button, pixelX: px, pixelY: py, button: 1 as int32, pressed: true, dx: 0.0, dy: 0.0 });
	deliverPointer(area, { kind: AreaPointerKind.Button, pixelX: px, pixelY: py, button: 1 as int32, pressed: false, dx: 0.0, dy: 0.0 });
}

function expect(area: WindowArea, px: float64, py: float64, want: string, label: string): void {
	log.length = 0;
	click(area, px, py);
	if (log.join("|") !== want) { fail(label + ": got '" + log.join("|") + "', expected '" + want + "'"); }
}

function init(): void {
	gfxSetup();
	const font = addFont("../void/assets/font.ttf");
	if (!font.ok) { fail("the test font did not load; run from the Neon checkout root beside ../void"); return; }
	const window: AreaWindow = {
		name: "Scene3D pointer device",
		font: font.value,
		pixelWidth: (): int32 => fbWidth(),
		pixelHeight: (): int32 => fbHeight(),
		requestFrame: (): void => {},
		dirty: (): void => {},
		setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => {},
		opened: (area: WindowArea): void => { areas.push(area); },
		released: (area: WindowArea): void => {},
	};
	render(element(
		<Void>
			<Scene3D onPressMissed={(e: NeonEvent): void => { log.push("missed"); }}>
				<Mesh geometry={square()} onPress={(e: Pointer3DEvent): void => { log.push("mesh"); }} />
			</Scene3D>
			<View style={{ width: 40, height: 40 }} onPointerDown={(e: NeonEvent): void => { log.push("view"); }} />
		</Void>
	), windowHost(window), windowNode("window"));
}

function frame(): void {
	if (areas.length !== 1) { fail("the window opened " + areas.length.toString() + " areas"); return; }
	const area = areas[0];
	if (frames === 0) { deliverResize(area, fbWidth(), fbHeight(), dpiScale() as float64); }
	if (!drawArea(area)) { fail("the area did not draw"); return; }
	frames += 1;
	if (frames < 2) { return; }
	const dpi = dpiScale() as float64;
	expect(area, (fbWidth() as float64) / 2.0, (fbHeight() as float64) / 2.0, "mesh", "the centre of the framebuffer");
	expect(area, 10.0 * dpi, 10.0 * dpi, "view", "the View over the scene");
	expect(area, (fbWidth() as float64) - 10.0 * dpi, (fbHeight() as float64) - 10.0 * dpi, "missed", "an empty corner");
	console.log("PASS Scene3D pointer device: framebuffer " + fbWidth().toString() + "x" + fbHeight().toString() + " at dpi " + dpi.toString() + "; mesh, View and miss routed through the window host");
	process.exit(0);
}

voidRun(400, 400, init, frame);
