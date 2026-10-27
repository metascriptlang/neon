import { createVoidHostWith, VoidHost, VoidNode } from "../../src/platform/void/host";
import { Scene2D, group, text } from "../../../void/src/void2d/node";
import { create, close } from "../../../void/src/void2d/scene";
import { addFont } from "../../../void/src/void2d/font";
import { rgba } from "../../../void/src/void2d/types";

function scoped(): VoidHost {
	const font = addFont("../void/assets/font.ttf");
	if (!font.ok) { throw new Error("test font unreadable"); }
	return createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), font.value, null, true);
}

test "scoped root accepts empty markers and refuses visible strings without reading undrawn refs" {
	const vh = scoped();
	try {
		const anchor = vh.host.createText("");
		vh.host.append(vh.root, anchor);
		assert vh.host.parentOf(anchor) === vh.root;
		let dynamic = "";
		try { vh.host.setText(anchor, "dynamic"); } catch (error) { dynamic = error.message; }
		assert dynamic.includes("Scene2D") && dynamic.includes("Label");
		let visible = "";
		try { vh.host.append(vh.root, vh.host.createText("visible")); }
		catch (error) { visible = error.message; }
		assert visible.includes("Scene2D") && visible.includes("Label");
		assert vh.tree.childrenOf(vh.root as VoidNode).length === 1;
	} finally { vh.scene.close(); }
}

test "scoped raw insertion accepts markers while mapped UI still owns visible text" {
	const vh = scoped();
	try {
		const raw = new VoidNode(vh.scene.group(), true);
		vh.host.append(vh.root, raw);
		const view = vh.host.createElement("view");
		vh.host.append(raw, view);
		const anchor = vh.host.createText("");
		vh.host.insertBefore(raw, anchor, view);
		assert vh.tree.childrenOf(raw)[0] === anchor && vh.tree.childrenOf(raw)[1] === view;
		let visible = "";
		const label = vh.host.createText("visible");
		try { vh.host.insertBefore(raw, label, view); } catch (error) { visible = error.message; }
		assert visible.includes("Scene2D") && visible.includes("Label");
		vh.host.append(view, label);
		assert vh.host.parentOf(label) === view;
		vh.host.setText(label, "mapped UI");
		assert (label as VoidNode).ref.text() === "mapped UI";
		assert vh.tree.childrenOf(raw).length === 2;
	} finally { vh.scene.close(); }
}
