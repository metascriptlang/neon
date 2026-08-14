// Array layering (docs/STYLE.md §2, S3): `style={[base, override]}`, later layer
// wins. Layers stay distinguishable in source — that is the Studio constraint (§1)
// that ruled out spread. Two emission paths, one meaning:
//   all layers object literals  → merged at expansion, no runtime call
//   any layer a sheet reference → nested mergeStyle() calls
// Asserted on NeonNode.style rather than through a host, so both lanes run it.

import { element } from "../../src/macros/ui/element";
import { el, attr, evt, text, dynText, withStyle, NeonNode } from "../../src/render/node";
import { Style, mergeStyle, layerStyles } from "../../src/render/style";
import { createStyles, styleOf } from "../../src/macros/ui/style";

const sheet = createStyles({
	box: { flexDirection: "column", width: 200, height: 120 },
	row: { height: 20 },
});

function styleOfNode(n: NeonNode): Style {
	return n.style as Style;
}

test "mergeStyle takes the later layer for a set field" {
	const merged = mergeStyle(styleOf({ width: 200, height: 120 }), styleOf({ height: 20 }));
	assert merged.height === 20, "later layer wins";
	assert merged.width === 200, "base survives where the override is unset";
}

test "mergeStyle leaves a field unset when neither layer sets it" {
	const merged = mergeStyle(styleOf({ width: 10 }), styleOf({ height: 5 }));
	assert merged.opacity === null, "untouched field stays unset";
	assert merged.width === 10, "base field kept";
	assert merged.height === 5, "override field kept";
}

test "two static layers merge at expansion" {
	const node = element(<div style={[{ width: 200, height: 120 }, { height: 20 }]}></div>);
	assert node.style !== null, "a layer array attaches a style";
	const s = styleOfNode(node);
	assert s.width === 200, "base width";
	assert s.height === 20, "override height wins";
}

test "three static layers apply left to right" {
	const node = element(<div style={[{ width: 1 }, { width: 2 }, { width: 3 }]}></div>);
	assert styleOfNode(node).width === 3, "last layer wins";
}

test "a sheet entry layers with a local override" {
	const node = element(<div style={[sheet.box, { height: 20 }]}></div>);
	const s = styleOfNode(node);
	assert s.width === 200, "sheet width flows through";
	assert s.height === 20, "local override wins";
	assert s.flexDirection === "column", "sheet field untouched by the override";
}

test "two sheet entries layer" {
	const node = element(<div style={[sheet.box, sheet.row]}></div>);
	const s = styleOfNode(node);
	assert s.height === 20, "later sheet entry wins";
	assert s.width === 200, "earlier entry survives";
}

test "a single-element layer array is still a style" {
	const node = element(<div style={[sheet.row]}></div>);
	assert styleOfNode(node).height === 20, "one layer applies unchanged";
}
