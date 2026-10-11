import { createRoot } from "../../src/core/owner";
import { element } from "../../src/macros/ui/element";
import { neonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render, fireEventWith } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import { ListWheelScrollView, WheelRenderItemInfo, selectedIndex, wheelPaint } from "../../src/components/listWheel";

interface Hour {
	label: string;
}

function hours(): Hour[] {
	const out: Hour[] = [];
	for (let i = 0; i < 24; i += 1) { out.push({ label: "h" + i.toString() }); }
	return out;
}

test "the selected item flips at the half-item boundary and clamps to the data" {
	assert selectedIndex(0, 40, 24) === 0, "rest";
	assert selectedIndex(19, 40, 24) === 0, "under half";
	assert selectedIndex(21, 40, 24) === 1, "past half";
	assert selectedIndex(5000, 40, 24) === 23, "clamped";
}

test "an item on the wheel shrinks and fades with its angle and disappears past a quarter turn" {
	const centre = wheelPaint(100, 100, 200, 2, 1, 40);
	assert centre.visible && centre.scaleY === 1 && centre.translateY === 0, "the centred item is flat";
	const off = wheelPaint(180, 100, 200, 2, 1, 40);
	assert off.visible && off.scaleY < 1 && off.translateY < 0 && off.opacity < 1, "80 pt away tilts towards the centre";
	const gone = wheelPaint(500, 100, 200, 2, 1, 40);
	assert !gone.visible, "400 pt away is behind the cylinder";
	const magnified = wheelPaint(105, 100, 200, 2, 1.2, 40);
	assert magnified.scaleY > 1, "the centre band magnifies";
}

test "a ListWheelScrollView reports the selected hour while scrolling and snaps when the scroll settles" {
	const selections: number[] = [];
	const root = mockNode("root");
	createRoot((): void => {
		render(element(<ListWheelScrollView data={hours()} itemExtent={40} style={{ height: 200 }}
			onSelectedItemChanged={(index: number): void => { selections.push(index); }}
			renderItem={(info: WheelRenderItemInfo<Hour>): NeonNode => <Text>{info.item.label}</Text>} />), mockHost(), root as unknown as HostNode);
	});
	const scroll = root.children[0];
	const at = (y: number): void => {
		const e = neonEvent("scroll");
		e.y = y;
		e.height = 200;
		fireEventWith(scroll, "onScroll", e);
	};
	at(30);
	at(70);
	at(95);
	assert selections.join(",") === "1,2", "1 then 2: " + selections.join(",");
	fireEventWith(scroll, "onMomentumScrollEnd", neonEvent("momentumscrollend"));
	assert scroll.scrollY === 80 && scroll.scrollAnimated, "snapped to item 2 at 80: " + scroll.scrollY.toString();
}
