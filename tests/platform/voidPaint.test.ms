import { Style } from "../../src/render/style";
import { createVoidHost, VoidHost, VoidNode, parseColor } from "../../src/platform/void/host";
import { DrawKind, kind, paint } from "../../../void/src/void2d/node";
import { Color } from "../../../void/src/void2d/types";
import { BoxStyle, boxStyles } from "../../../void/src/void2d/boxStyle";

function boxOf(vh: VoidHost, n: VoidNode): BoxStyle {
	return boxStyles[vh.scene.payloads[n.ref.id.index]];
}

function near(a: float32, b: number): boolean {
	return Math.abs((a as number) - b) < 0.002;
}

test "a View's border, corner radius and box shadow paint on the Void host" {
	const vh = createVoidHost();
	const n = vh.host.createElement("div") as VoidNode;
	vh.host.setStyle(n, {
		backgroundColor: "#ffffff", borderRadius: 8, borderWidth: 2, borderColor: "#ff0000",
		boxShadow: "0 4px 6px rgba(0, 0, 0, 0.3), inset 1px 1px 0 #00ff0080",
	} as Style);
	assert n.ref.kind() === DrawKind.Rect, "a boxed view draws as a rect";
	assert n.ref.paint().color.g > 0.99, "its background stays the fill";
	const box = boxOf(vh, n);
	assert near(box.radii.topLeft, 8) && near(box.radii.bottomRight, 8), "radius " + box.radii.topLeft.toString();
	assert near(box.borders.left, 2) && near(box.borders.bottom, 2), "border width " + box.borders.left.toString();
	assert near(box.borderColor.r, 1) && near(box.borderColor.g, 0), "border colour";
	assert box.shadows.length === 2, "two shadows";
	const drop = box.shadows[0];
	assert !drop.inset && near(drop.offsetX, 0) && near(drop.offsetY, 4) && near(drop.blur, 3) && near(drop.color.a, 0.3),
		`drop shadow ${drop.offsetY} ${drop.blur} ${drop.color.a}`;
	const inner = box.shadows[1];
	assert inner.inset && near(inner.offsetX, 1) && near(inner.color.g, 1) && near(inner.color.a, 128.0 / 255.0), "inset shadow";
}

test "a border on a view with no background draws over a clear fill, and dropping it unboxes the view" {
	const vh = createVoidHost();
	const n = vh.host.createElement("div") as VoidNode;
	vh.host.setStyle(n, { borderWidth: 1 } as Style);
	assert n.ref.kind() === DrawKind.Rect && n.ref.paint().color.a === 0.0, "clear fill under the border";
	const box = boxOf(vh, n);
	assert near(box.borders.top, 1) && near(box.borderColor.a, 1) && near(box.borderColor.r, 0), "RN's default border colour is black";
	vh.host.setStyle(n, { backgroundColor: "#000000" } as Style);
	const after = boxOf(vh, n);
	assert near(after.borders.top, 0) && near(after.radii.topLeft, 0) && after.shadows.length === 0, "no border left";
}

test "a colour or shadow the Void host cannot read is refused by name" {
	const vh = createVoidHost();
	let message = "";
	try { vh.host.setStyle(vh.host.createElement("div"), { borderWidth: 1, borderColor: "tomato" } as Style); } catch (e) { message = e.message; }
	assert message.indexOf(`borderColor "tomato" is not a colour`) >= 0, "borderColor: " + message;
	message = "";
	try { vh.host.setStyle(vh.host.createElement("div"), { boxShadow: "2px #000" } as Style); } catch (e) { message = e.message; }
	assert message.indexOf("needs two to four lengths") >= 0, "boxShadow: " + message;
}

test "parseColor reads the eight-digit hex and rgb() forms" {
	const a = parseColor("#11223380") as Color;
	assert near(a.r, 17.0 / 255.0) && near(a.a, 128.0 / 255.0), "#rrggbbaa";
	const b = parseColor("rgba(255, 0, 0, 0.5)") as Color;
	assert near(b.r, 1) && near(b.a, 0.5), "rgba()";
	const c = parseColor("rgb(0, 255, 0)") as Color;
	assert near(c.g, 1) && near(c.a, 1), "rgb()";
	assert parseColor("tomato") === null, "a name stays unread";
}
