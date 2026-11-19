import { createVoidHostWith, VoidHost, VoidNode } from "../../src/platform/void/host";
import { Scene2D, DrawKind, NodeRef } from "../../../void/src/void2d/node";
import { create } from "../../../void/src/void2d/scene";
import { rgba } from "../../../void/src/void2d/types";
import { FontId, addFont } from "../../../void/src/void2d/font";
import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { NeonNode } from "../../src/render/hostTypes";
import { View } from "../../src/components/primitives";
import { Overflow } from "../../src/render/style";

function testFont(): FontId {
	const font = addFont("../void/assets/font.ttf");
	if (!font.ok) { throw new Error("the test font ../void/assets/font.ttf did not load"); }
	return font.value;
}

const FONT = testFont();

function mounted(app: NeonNode): VoidHost {
	const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), FONT);
	render(app, vh.host, vh.root);
	vh.layout(400.0, 400.0);
	return vh;
}

function card(vh: VoidHost): VoidNode { return vh.tree.childrenOf(vh.root as VoidNode)[0]; }

test "a View with overflow hidden clips its children to its rounded box" {
	const vh = mounted(element(
		<View style={{ width: 100, height: 100, borderRadius: 10, overflow: "hidden" }}>
			<View style={{ width: 200, height: 200, backgroundColor: "#ff0000" }} />
		</View>
	));
	const c = card(vh);
	const m = c.clip;
	assert m !== null, "the card holds a clip";
	assert (m as NodeRef).kind() === DrawKind.Mask, "the clip is a void2d Mask";
	assert (m as NodeRef).scroll().radii.topLeft === 10.0, `rounded by the card's borderRadius, got ${(m as NodeRef).scroll().radii.topLeft}`;
	assert (m as NodeRef).content().w === 100.0 && (m as NodeRef).content().h === 100.0, "the clip is the card's box";
	const inside = vh.hitAt(50.0, 50.0);
	assert inside !== null && inside !== c, "a point inside the card hits the child";
	const outside = vh.hitAt(150.0, 150.0);
	assert outside === null || outside === vh.root, `a point past the card's edge does not reach the clipped child, got ${outside === null ? "null" : (outside as VoidNode).tag}`;
}

test "overflow back to visible returns the children to the View and drops the clip" {
	const [over, setOver] = createSignal<Overflow>("hidden");
	const vh = mounted(element(
		<View style={{ width: 100, height: 100, overflow: over() }}>
			<View style={{ width: 200, height: 200, backgroundColor: "#ff0000" }} />
		</View>
	));
	const c = card(vh);
	assert c.clip !== null, "clipped while hidden";
	setOver("visible");
	flush();
	vh.layout(400.0, 400.0);
	assert c.clip === null, "no clip once visible";
	const outside = vh.hitAt(150.0, 150.0);
	assert outside !== null && outside !== c && outside !== vh.root, "the child is hit past the card's edge again";
}
