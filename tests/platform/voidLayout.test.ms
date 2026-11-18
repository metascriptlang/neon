import {
	createVoidHostWith, VoidHost, VoidNode,
} from "../../src/platform/void/host";
import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { View, Text } from "../../src/components/primitives";
import { TouchableWithoutFeedback } from "../../src/components/touchable";
import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import {
	Scene2D, NodeRef, group, label, local, content, setPosition, setSize,
} from "../../../void/src/void2d/node";
import { create, close } from "../../../void/src/void2d/scene";
import { addFont } from "../../../void/src/void2d/font";
import { rgba } from "../../../void/src/void2d/types";

function host(): VoidHost {
	const font = addFont("../void/assets/font.ttf");
	if (!font.ok) { throw new Error("test font unreadable"); }
	return createVoidHostWith(
		Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), font.value,
	);
}

function child(vh: VoidHost, n: VoidNode): VoidNode {
	return vh.tree.childrenOf(n)[0];
}

test "unstyled View and WithoutFeedback lay out and deliver enabled presses" {
	const vh = host();
	const [disabled, setDisabled] = createSignal(true);
	let presses: int32 = 0;
	const dispose = render(element(
		<View>
			<TouchableWithoutFeedback disabled={disabled()}
				onPress={() => { presses += 1; }}>
				<View style={{ width: 120, height: 40 }}><Text>Tap</Text></View>
			</TouchableWithoutFeedback>
		</View>
	), vh.host, vh.root);
	try {
		vh.layout(320.0, 200.0);
		const outer = child(vh, vh.root as VoidNode);
		const pressable = child(vh, outer);
		const inner = child(vh, pressable);
		assert outer.ref.content().w === 320.0;
		assert outer.ref.content().h === 40.0;
		assert pressable.ref.content().w === 320.0;
		assert pressable.ref.content().h === 40.0;
		assert inner.ref.content().w === 120.0;
		assert inner.ref.content().h === 40.0;
		assert child(vh, inner).ref.content().h > 0.0;
		assert vh.pointerDown(10.0, 10.0, 1);
		assert vh.pointerUp(10.0, 10.0, 1);
		flush();
		assert presses === 0;
		setDisabled(false);
		flush();
		assert vh.pointerDown(10.0, 10.0, 1);
		assert vh.pointerUp(10.0, 10.0, 1);
		flush();
		assert presses === 1;
	} finally { dispose(); vh.scene.close(); }
}

test "unstyled ScrollView lays out its viewport mask and descendants" {
	const vh = host();
	try {
		const scroll = vh.host.createElement("scrollview") as VoidNode;
		const inner = vh.host.createElement("view") as VoidNode;
		vh.host.setStyle(inner, { width: 90, height: 60 });
		vh.host.append(vh.root, scroll);
		vh.host.append(scroll, inner);
		vh.layout(320.0, 200.0);
		assert scroll.ref.content().w === 320.0;
		assert scroll.ref.content().h === 60.0;
		assert scroll.scroller !== null;
		const mask = scroll.scroller as NodeRef;
		assert mask.content().w === 320.0 && mask.content().h === 60.0;
		assert inner.ref.content().w === 90.0;
		assert inner.ref.content().h === 60.0;
	} finally { vh.scene.close(); }
}

test "createElement defaults leave manual nodes and inline text outside Yoga" {
	const vh = host();
	try {
		const manual = new VoidNode(vh.scene.group());
		manual.ref.setPosition(31.0, 17.0).setSize(100.0, 70.0);
		vh.host.append(vh.root, manual);
		const ui = vh.host.createElement("holder") as VoidNode;
		vh.host.append(vh.root, ui);
		vh.host.setStyle(ui, { height: 25 });
		const first = vh.host.createText("first") as VoidNode;
		const second = vh.host.createText("second") as VoidNode;
		vh.host.append(ui, first);
		vh.host.append(ui, second);
		second.ref.setPosition(99.0, 5.0);
		vh.layout(320.0, 200.0);
		assert manual.flex === null && manual.yg === null;
		assert manual.ref.local().x === 31.0 && manual.ref.local().y === 17.0;
		assert manual.ref.content().w === 100.0;
		assert manual.ref.content().h === 70.0;
		assert ui.ref.local().y === 0.0 && ui.ref.content().w === 320.0;
		assert first.flex === null && first.yg === null;
		assert second.flex === null && second.yg === null;
		assert first.ref.local().x === 0.0;
		assert second.ref.local().x > 0.0 && second.ref.local().x < 99.0;
		assert second.ref.local().y === 5.0;
	} finally { vh.scene.close(); }
}

test "an unstyled UI island under raw content lays out without moving raw nodes" {
	const vh = host();
	try {
		const raw = new VoidNode(vh.scene.group(), true);
		raw.ref.setPosition(43.0, 19.0).setSize(180.0, 90.0);
		vh.host.append(vh.root, raw);
		const ui = vh.host.createElement("view") as VoidNode;
		const inner = vh.host.createElement("view") as VoidNode;
		vh.host.setStyle(inner, { width: 80, height: 30 });
		vh.host.append(raw, ui);
		vh.host.append(ui, inner);
		const rawLabel = new VoidNode(
			vh.scene.label("raw", 14.0, rgba(1.0, 1.0, 1.0, 1.0)), true,
		);
		rawLabel.ref.setPosition(23.0, 7.0).setSize(35.0, 20.0);
		vh.host.append(raw, rawLabel);
		vh.layout(320.0, 200.0);
		assert raw.yg === null && rawLabel.yg === null;
		assert raw.ref.local().x === 43.0 && raw.ref.local().y === 19.0;
		assert raw.ref.content().w === 180.0 && raw.ref.content().h === 90.0;
		assert rawLabel.ref.local().x === 23.0;
		assert rawLabel.ref.local().y === 7.0;
		assert rawLabel.ref.content().w === 35.0;
		assert rawLabel.ref.content().h === 20.0;
		assert ui.ref.content().w === 180.0 && ui.ref.content().h === 90.0;
		assert inner.ref.content().w === 80.0 && inner.ref.content().h === 30.0;
	} finally { vh.scene.close(); }
}
