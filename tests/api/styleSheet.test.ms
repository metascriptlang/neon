import { StyleSheet } from "../../src/api/styleSheet";
import { publishScale } from "../../src/api/dimensions";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { View } from "../../src/components/primitives";

test "StyleSheet.hairlineWidth is the thinnest line on the pixel grid" {
	publishScale(3, 1);
	const three = StyleSheet.hairlineWidth;
	publishScale(2, 1);
	const two = StyleSheet.hairlineWidth;
	publishScale(1, 1);
	const one = StyleSheet.hairlineWidth;
	assert Math.abs(three - 1.0 / 3.0) < 0.0001, "3x: " + three.toString();
	assert two === 0.5, "2x: " + two.toString();
	assert one === 1, "1x: " + one.toString();
}

test "StyleSheet.absoluteFill pins all four edges and layers under an author style" {
	const sheet = createStyles({ tint: { backgroundColor: "#ff0000" } });
	const root: MockNode = mockNode("root");
	render(element(<View style={[StyleSheet.absoluteFill, sheet.tint]} />), mockHost(), root as unknown as HostNode);
	const s = root.children[0].style as Style;
	assert s.position === "absolute" && s.left === 0 && s.right === 0 && s.top === 0 && s.bottom === 0, "fill";
	assert s.backgroundColor === "#ff0000", "tint";
	assert StyleSheet.absoluteFillObject.position === "absolute", "the object form";
}

test "StyleSheet.flatten and compose layer later styles over earlier ones" {
	const a: Style = { padding: 4, margin: 2 };
	const b: Style = { padding: 8, color: "#fff" };
	const flat = StyleSheet.flatten([a, null, b]);
	assert flat.padding === 8 && flat.margin === 2 && flat.color === "#fff", "flatten";
	const composed = StyleSheet.compose(a, b);
	assert composed.padding === 8 && composed.margin === 2, "compose";
	assert StyleSheet.compose(null, b).padding === 8 && StyleSheet.compose(a, null).padding === 4, "compose with null";
	assert StyleSheet.flatten([]).padding === null, "empty";
}
