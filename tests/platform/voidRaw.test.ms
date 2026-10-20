import { createSignal } from "../../src/core/signal";
import { createRenderEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { flush } from "../../src/core/runtime";
import { createRoot } from "../../src/core/owner";
import { createVoidHostWith, VoidHost, VoidNode } from "../../src/platform/void/host";
import { Style } from "../../src/render/style";
import {
	group, label, rect, local, content, setPosition, setSize,
	getChildIndex, isLive, clearChanges, text, textStyle, parent, kind, DrawKind, paint,
} from "../../../void/src/void2d/node";
import { Scene2D } from "../../../void/src/void2d/node";
import { addFont } from "../../../void/src/void2d/font";
import { create, paint as paintScene, isDirty, close } from "../../../void/src/void2d/scene";
import { frameEnd } from "../../../void/src/void2d/draw";
import { rgba, ScaleMode } from "../../../void/src/void2d/types";

function host(scoped: boolean = false): VoidHost {
	const font = addFont("../void/assets/font.ttf");
	if (!font.ok) { throw new Error("test font unreadable"); }
	return createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), font.value, null, scoped);
}

function settle(vh: VoidHost): void {
	vh.layout(400.0, 300.0);
	vh.scene.paintScene(400.0, 300.0, 1.0);
	frameEnd();
	vh.scene.clearChanges();
}

test "raw wrappers use actual host parent, insertion, move and subtree disposal" {
	const vh = host();
	try {
		const group = new VoidNode(vh.scene.group(), true);
		const first = new VoidNode(vh.scene.rect(2.0, 3.0, rgba(1.0, 1.0, 1.0, 1.0)), true);
		const second = vh.host.createElement("view") as VoidNode;
		const inserted = new VoidNode(vh.scene.group(), true);
		vh.host.append(vh.root, group);
		vh.host.append(group, first);
		vh.host.append(group, second);
		vh.host.insertBefore(group, inserted, second);
		assert group.children[0] === first && group.children[1] === inserted;
		const next = vh.host.nextSibling(inserted);
		assert next !== null;
		assert (next as VoidNode) === second;
		assert group.ref.getChildIndex(inserted.ref) === 1;
		vh.host.insertBefore(group, second, first);
		assert group.children[0] === second && group.ref.getChildIndex(second.ref) === 0;
		vh.host.append(vh.root, inserted);
		assert inserted.parent === vh.root && group.children.length === 2;
		vh.host.removeChild(vh.root, group);
		assert group.disposed && first.disposed && second.disposed;
		assert !group.ref.isLive() && !first.ref.isLive() && !second.ref.isLive();
		assert inserted.ref.isLive();
		let caught = "";
		try { vh.host.append(vh.root, first); } catch (error) { caught = error.message; }
		assert caught.includes("removed and freed");
	} finally { vh.scene.close(); }
}

test "full layout preserves raw Label pose and size while UI text still flows" {
	const vh = host();
	try {
		const raw = new VoidNode(vh.scene.label("raw", 16.0, rgba(1.0, 1.0, 1.0, 1.0)), true);
		raw.ref.setPosition(42.0, 17.0).setSize(30.0, 20.0);
		vh.host.append(vh.root, raw);
		vh.host.setStyle(raw, { width: 90, height: 80 } as Style);
		const first = vh.host.createText("first") as VoidNode;
		const second = vh.host.createText("second") as VoidNode;
		second.ref.setPosition(99.0, 5.0);
		vh.host.append(vh.root, first);
		vh.host.append(vh.root, second);
		vh.layout(400.0, 300.0);
		assert raw.ref.local().x === 42.0 && raw.ref.local().y === 17.0;
		assert raw.ref.content().w === 30.0 && raw.ref.content().h === 20.0;
		assert raw.yg === null;
		assert second.ref.local().x > 0.0 && second.ref.local().x < 99.0,
			"UI Label still takes inline flow position";
	} finally { vh.scene.close(); }
}

test "UI parent text paint never overwrites raw Label props on insertion restyle or reorder" {
	const vh = host();
	try {
		const parent = vh.host.createElement("view") as VoidNode;
		vh.host.append(vh.root, parent);
		vh.host.setStyle(parent, { color: "#ff0000", fontSize: 32 } as Style);
		const first = new VoidNode(vh.scene.label("raw first", 16.0, rgba(0.0, 1.0, 0.0, 1.0)), true);
		const second = new VoidNode(vh.scene.label("raw second", 16.0, rgba(0.0, 1.0, 0.0, 1.0)), true);
		const ui = vh.host.createText("UI") as VoidNode;
		vh.host.append(parent, first);
		vh.host.append(parent, second);
		vh.host.append(parent, ui);
		const firstId = first.ref.id;
		const secondId = second.ref.id;
		assert first.ref.textStyle().size === 16.0 && first.ref.paint().color.g === 1.0;
		assert second.ref.textStyle().size === 16.0 && second.ref.paint().color.g === 1.0;
		assert ui.ref.textStyle().size === 32.0 && ui.ref.paint().color.r === 1.0;
		vh.host.setStyle(parent, { color: "#0000ff", fontSize: 40 } as Style);
		assert first.ref.textStyle().size === 16.0 && first.ref.paint().color.g === 1.0;
		assert ui.ref.textStyle().size === 40.0 && ui.ref.paint().color.b === 1.0;
		vh.host.insertBefore(parent, second, first);
		assert parent.children[0] === second && parent.children[1] === first;
		assert first.ref.id === firstId && second.ref.id === secondId;
		assert first.ref.textStyle().size === 16.0 && first.ref.paint().color.g === 1.0;
		assert second.ref.textStyle().size === 16.0 && second.ref.paint().color.g === 1.0;
	} finally { vh.scene.close(); }
}

test "raw mutation effects wake existing listener once per clean scene, including throw" {
	const vh = host();
	const raw = new VoidNode(vh.scene.group(), true);
	vh.host.append(vh.root, raw);
	let wakes: int32 = 0;
	vh.onDirty((): void => { wakes += 1; });
	const [x, setX] = createSignal<float32>(1.0);
	const dispose = createRoot((dispose) => {
		createRenderEffect<float32>(
			(prev: float32 | null): float32 => x(),
			(value: float32, prev: float32 | null): Cleanup | null => {
				vh.mutate((): void => { raw.ref.setPosition(value, 0.0); });
				return null;
			},
		);
		return dispose;
	});
	try {
		settle(vh);
		assert !vh.scene.isDirty();
		setX(2.0);
		flush();
		assert wakes === 1;
		setX(3.0);
		flush();
		assert wakes === 1;
		settle(vh);
		let caught = "";
		try {
			vh.mutate((): void => {
				raw.ref.setPosition(4.0, 0.0);
				throw new Error("partial raw mutation");
			});
		} catch (error) { caught = error.message; }
		assert caught === "partial raw mutation" && wakes === 2;
		settle(vh);
		vh.mutate((): void => {});
		assert wakes === 2 && !vh.scene.isDirty();
	} finally { dispose(); vh.scene.close(); }
}


test "UI islands use authored raw boxes, resize and cross nested raw boundaries" {
	const vh = host();
	try {
		const raw = new VoidNode(vh.scene.group(), true);
		raw.ref.setPosition(11.0, 13.0).setSize(120.0, 80.0);
		vh.host.append(vh.root, raw);
		const ui = vh.host.createElement("view") as VoidNode;
		vh.host.setStyle(ui, { width: 40, height: 20 } as Style);
		vh.host.append(raw, ui);
		const percent = vh.host.createElement("view") as VoidNode;
		percent.flex = { width: "50%", height: "50%" };
		vh.host.append(raw, percent);
		const nested = new VoidNode(vh.scene.group(), true);
		nested.ref.setSize(60.0, 40.0);
		vh.host.append(ui, nested);
		const inner = vh.host.createElement("view") as VoidNode;
		inner.flex = { width: "50%", height: "50%" };
		vh.host.append(nested, inner);
		vh.layout(400.0, 300.0);
		assert ui.ref.content().w === 40.0 && ui.ref.content().h === 20.0;
		assert percent.ref.content().w === 60.0 && percent.ref.content().h === 40.0;
		assert inner.ref.content().w === 30.0 && inner.ref.content().h === 20.0;
		assert raw.yg === null && nested.yg === null;
		raw.ref.setSize(200.0, 100.0);
		vh.layout(400.0, 300.0);
		assert percent.ref.content().w === 100.0 && percent.ref.content().h === 50.0;
		assert raw.ref.local().x === 11.0 && raw.ref.local().y === 13.0;
		vh.host.append(vh.root, ui);
		assert ui.yg === null && inner.yg === null;
		vh.layout(400.0, 300.0);
		assert ui.yg !== null && inner.yg !== null;
		vh.host.append(raw, ui);
		assert ui.yg === null && inner.yg === null;
		vh.layout(400.0, 300.0);
		assert ui.ref.content().w === 40.0 && inner.ref.content().w === 30.0;
		vh.host.removeChild(vh.root, raw);
		assert ui.yg === null && inner.yg === null && raw.disposed && inner.disposed;
	} finally { vh.scene.close(); }
}


test "scene property changes wake once without engine dirty and unchanged values stay asleep" {
	const vh = host();
	let wakes: int32 = 0;
	vh.onDirty((): void => { wakes += 1; });
	try {
		settle(vh);
		vh.mutate((): void => { vh.scene.clear = rgba(0.3, 0.0, 0.0, 1.0); });
		assert !vh.scene.isDirty() && wakes === 1;
		vh.mutate((): void => { vh.scene.clear = rgba(0.4, 0.0, 0.0, 1.0); });
		assert wakes === 1;
		settle(vh);
		vh.mutate((): void => { vh.scene.clear = rgba(0.4, 0.0, 0.0, 1.0); });
		assert wakes === 1;
		vh.mutate((): void => { vh.scene.designW = 120.0; });
		assert wakes === 2;
		settle(vh);
		vh.mutate((): void => { vh.scene.designW = 120.0; });
		assert wakes === 2;
		vh.mutate((): void => { vh.scene.cam = { ...vh.scene.cam, x: 1.0 }; });
		assert wakes === 3;
		settle(vh);
		vh.mutate((): void => { vh.scene.cam = { ...vh.scene.cam, x: 1.0 }; });
		assert wakes === 3;
		vh.mutate((): void => { vh.scene.defaultSmooth = false; });
		assert wakes === 4;
		settle(vh);
		vh.mutate((): void => { vh.scene.defaultSmooth = false; });
		assert wakes === 4;
		vh.mutate((): void => { vh.scene.scaleMode = ScaleMode.Stretch; });
		assert wakes === 5;
		settle(vh);
		vh.mutate((): void => { vh.scene.scaleMode = ScaleMode.Stretch; });
		assert wakes === 5;
		vh.mutate((): void => { vh.scene.designH = 80.0; });
		assert wakes === 6;
		settle(vh);
		vh.mutate((): void => { vh.scene.designH = 80.0; });
		assert wakes === 6;
	} finally { vh.scene.close(); }
}

test "scene changes from onLayout are consumed before the next clean-frame wake" {
	const vh = host();
	let wakes: int32 = 0;
	let layouts: int32 = 0;
	vh.onDirty((): void => { wakes += 1; });
	try {
		const view = vh.host.createElement("view") as VoidNode;
		vh.host.setStyle(view, { width: 40, height: 20 } as Style);
		vh.host.append(vh.root, view);
		const raw = new VoidNode(vh.scene.group(), true);
		vh.host.append(vh.root, raw);
		vh.host.addEvent(view, "onLayout", (): void => {
			layouts += 1;
			vh.mutate((): void => { vh.scene.clear = rgba(0.3, 0.0, 0.0, 1.0); });
		});
		settle(vh);
		assert layouts === 1 && !vh.scene.isDirty();
		const before = wakes;
		vh.mutate((): void => { raw.ref.setPosition(10.0, 0.0); });
		assert wakes === before + 1;
		settle(vh);
		vh.mutate((): void => { raw.ref.setPosition(20.0, 0.0); });
		assert wakes === before + 2 && layouts === 1;
	} finally { vh.scene.close(); }
}

test "scoped host rejects direct raw text and intrinsics but allows mapped UI text" {
	const vh = host(true);
	try {
		let intrinsic = "";
		try { vh.host.createElement("div"); } catch (error) { intrinsic = error.message; }
		assert intrinsic.includes("Scene2D") && intrinsic.includes("div");
		let nested = "";
		try { vh.host.createElement("void"); } catch (error) { nested = error.message; }
		assert nested.includes("Scene2D") && nested.includes("void");
		const label = vh.host.createText("not a Label");
		let visible = "";
		try { vh.host.append(vh.root, label); } catch (error) { visible = error.message; }
		assert visible.includes("Scene2D") && visible.includes("Label");
		const anchor = vh.host.createText("");
		vh.host.append(vh.root, anchor);
		let dynamic = "";
		try { vh.host.setText(anchor, "dynamic"); } catch (error) { dynamic = error.message; }
		assert dynamic.includes("Scene2D") && dynamic.includes("Label");
		const view = vh.host.createElement("view");
		vh.host.append(vh.root, view);
		vh.host.append(view, label);
		vh.host.setText(label, "UI text");
		assert (label as VoidNode).ref.text() === "UI text";
	} finally { vh.scene.close(); }
}


test "raw nodes keep ScrollView box background and inner Mask child-holder ordering" {
	const vh = host();
	try {
		const scroll = vh.host.createElement("scrollview") as VoidNode;
		vh.host.setStyle(scroll, { width: 100, height: 60, backgroundColor: "#ff0000" } as Style);
		vh.host.append(vh.root, scroll);
		const first = new VoidNode(vh.scene.group(), true);
		const second = new VoidNode(vh.scene.group(), true);
		vh.host.append(scroll, first);
		vh.host.append(scroll, second);
		vh.host.insertBefore(scroll, second, first);
		vh.layout(400.0, 300.0);
		const mask = scroll.scroller;
		assert mask !== null;
		assert scroll.ref.kind() === DrawKind.Rect && scroll.ref.paint().color.r === 1.0;
		assert mask.kind() === DrawKind.Mask && mask.getChildIndex(second.ref) === 0;
		const up = second.ref.parent();
		assert up !== null && up.id.index === mask.id.index;
		assert second.parent === scroll && scroll.children[0] === second;
		assert scroll.ref.content().w === 100.0 && mask.content().w === 100.0;
		vh.host.removeChild(vh.root, scroll);
		assert scroll.disposed && first.disposed && second.disposed && !mask.isLive();
	} finally { vh.scene.close(); }
}
