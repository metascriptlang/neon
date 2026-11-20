import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { Cursor } from "../../src/render/style";
import { AreaPointerKind } from "../../src/render/voidAreaHandle";
import { Void, View } from "../../src/components/primitives";
import { AreaWindow, WindowArea, windowHost, windowNode, deliverFramePointer, deliverResize } from "../../src/platform/void/windowHost";
import { ionCursor } from "../../src/platform/ion/window";
import { CursorArrow, CursorHand, CursorIbeam, CursorCross, CursorResizeH, CursorResizeV } from "../../../ion/src/index";
import { FontId, addFont } from "../../../void/src/void2d/font";

const FONT_PATH = "../void/assets/font.ttf";

function loadedFont(): FontId {
	const r = addFont(FONT_PATH);
	if (!r.ok) { throw new Error("the test font did not load from " + FONT_PATH + "; run from the Neon checkout root beside ../void"); }
	return r.value;
}

function cursorWindow(set: int32[], areas: WindowArea[]): AreaWindow {
	return {
		name: "cursor window",
		font: loadedFont(),
		pixelWidth: (): int32 => 400 as int32,
		pixelHeight: (): int32 => 200 as int32,
		requestFrame: (): void => {},
		dirty: (): void => {},
		setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => {},
		setCursor: (cursor: Cursor): void => { set.push(ionCursor(cursor)); },
		opened: (area: WindowArea): void => { areas.push(area); },
		released: (area: WindowArea): void => {},
	};
}

function splitPanes(set: int32[]): WindowArea {
	const areas: WindowArea[] = [];
	render(element(
		<Void>
			<View style={{ flexDirection: "row", width: 300, height: 100 }}>
				<View style={{ width: 100, height: 100 }} />
				<View style={{ width: 10, height: 100, cursor: "col-resize" }} />
				<View style={{ width: 100, height: 100, cursor: "row-resize" }}>
					<View style={{ width: 50, height: 50 }} />
				</View>
			</View>
		</Void>
	), windowHost(cursorWindow(set, areas)), windowNode("window"));
	const area = areas[0];
	deliverResize(area, 400 as int32, 200 as int32, 1.0);
	area.vh.layout(area.logicalWidth(), area.logicalHeight());
	return area;
}

function moveTo(area: WindowArea, x: float64, y: float64): void {
	deliverFramePointer(area, { kind: AreaPointerKind.Motion, pixelX: x, pixelY: y, button: 0 as int32, pressed: false, dx: 0.0, dy: 0.0 });
}

function button(area: WindowArea, x: float64, y: float64, pressed: boolean): void {
	deliverFramePointer(area, { kind: AreaPointerKind.Button, pixelX: x, pixelY: y, button: 1 as int32, pressed, dx: 0.0, dy: 0.0 });
}

function shown(set: int32[]): string {
	return set.map((c: int32): string => c.toString()).join(",");
}

test "hovering a col-resize View sets the resize cursor once, moving within it sets nothing, leaving it sets the arrow" {
	const set: int32[] = [];
	const area = splitPanes(set);
	moveTo(area, 50.0, 50.0);
	assert set.length === 0, "a View without cursor over the default sets nothing: " + shown(set);
	moveTo(area, 105.0, 50.0);
	assert shown(set) === `${CursorResizeH}`, shown(set);
	moveTo(area, 107.0, 60.0);
	assert shown(set) === `${CursorResizeH}`, "a move within the View sets nothing: " + shown(set);
	moveTo(area, 50.0, 50.0);
	assert shown(set) === `${CursorResizeH},${CursorArrow}`, shown(set);
}

test "a press keeps the cursor it started on while dragged over other Views, until release" {
	const set: int32[] = [];
	const area = splitPanes(set);
	moveTo(area, 105.0, 50.0);
	button(area, 105.0, 50.0, true);
	moveTo(area, 50.0, 50.0);
	moveTo(area, 180.0, 80.0);
	assert shown(set) === `${CursorResizeH}`, "a held press keeps the resize cursor: " + shown(set);
	button(area, 50.0, 50.0, false);
	assert shown(set) === `${CursorResizeH},${CursorArrow}`, "the release shows the cursor under the pointer: " + shown(set);
}

test "a child without cursor shows its nearest ancestor's" {
	const set: int32[] = [];
	const area = splitPanes(set);
	moveTo(area, 120.0, 20.0);
	assert shown(set) === `${CursorResizeV}`, shown(set);
	moveTo(area, 190.0, 80.0);
	assert shown(set) === `${CursorResizeV}`, "from the child to its parent the cursor stays: " + shown(set);
}

test "every cursor name maps to an Ion cursor" {
	const names: Cursor[] = ["auto", "default", "pointer", "text", "crosshair", "col-resize", "row-resize"];
	const ion = names.map((c: Cursor): string => ionCursor(c).toString()).join(",");
	assert ion === [CursorArrow, CursorArrow, CursorHand, CursorIbeam, CursorCross, CursorResizeH, CursorResizeV].join(","), ion;
}
