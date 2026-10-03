import { runApp } from "../../src/platform/native/host";
import { createSignal, Accessor } from "../../src/core/signal";
import { For } from "../../src/macros/ui/flow";
import { View, Pressable, ScrollView, ScrollViewHandle } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { Text } from "../../src/components/primitives";
import { FlatList, ItemLayout, ListRenderItemInfo } from "../../src/components/flatList";

import {
	nmViewsCreated, nmReleaseCalls, nmTouch, nmTeardown, nmMount, nmResize, nmScroll, nmLastScrollTag,
	nmContentWidth, nmContentHeight, nmScrolledX, nmScrolledY, nmScrolledAnimated, nmContentSizeWrites,
	nmScrollFrameWrites, nmScreenHeightReads,
} from "./nativeBridgeMock.h";

const PRESS: int32 = 2;

test "removed rows and a torn-down app release native views and routes exactly once" {
	const [rows, setRows] = createSignal<number[]>([1, 2, 3]);
	let pressed = "";
	const app = (): NeonNode => <View>
		<For each={rows()}>{(row: number, i: Accessor<number>): NeonNode =>
			<Pressable onPress={() => { pressed += row.toString() + ";"; }}>row</Pressable>}</For>
	</View>;

	runApp(app);
	const created = nmViewsCreated();
	const released = nmReleaseCalls();
	nmTouch(2, PRESS);
	assert pressed === "2;", "the second row's tag routes before removal: " + pressed;

	setRows([1, 3]);
	assert nmViewsCreated() === created, "keyed rows 1 and 3 are not recreated";
	assert nmReleaseCalls() - released === 2, "the removed row releases its pressable and its label: " + (nmReleaseCalls() - released).toString();
	nmTouch(2, PRESS);
	nmTouch(1, PRESS);
	nmTouch(3, PRESS);
	assert pressed === "2;1;3;", "the removed tag is inert, the others still route: " + pressed;

	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "every created view is released after teardown";
	nmTouch(1, PRESS);
	assert pressed === "2;1;3;", "no route survives teardown: " + pressed;

	nmMount();
	assert nmViewsCreated() > nmReleaseCalls(), "the remount creates fresh views";
	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "a second teardown releases the remount";
}


test "a ScrollView's native content size follows its laid-out content, also after a rotation" {
	const app = (): NeonNode => <ScrollView style={{ height: 200 }}>
		<View style={{ height: 300 }} />
		<View style={{ height: 300 }} />
	</ScrollView>;
	runApp(app);
	assert `${nmContentWidth()} ${nmContentHeight()}` === "400 600", "portrait: " + `${nmContentWidth()} ${nmContentHeight()}`;
	nmResize(800, 400);
	assert `${nmContentWidth()} ${nmContentHeight()}` === "800 600", "landscape: " + `${nmContentWidth()} ${nmContentHeight()}`;
	nmResize(400, 800);
	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "the scroll view is released with the rest";
}

test "onScroll on a native ScrollView carries the native offset, viewport and content size" {
	let got = "";
	const app = (): NeonNode => <ScrollView onScroll={(e: NeonEvent): void => {
		got = `${e.type} ${e.x} ${e.y} ${e.width} ${e.height} ${e.contentWidth} ${e.contentHeight}`;
	}}>
		<View style={{ height: 900 }} />
	</ScrollView>;
	runApp(app);
	nmScroll(nmLastScrollTag(), 0, 120, 400, 800, 400, 900);
	assert got === "scroll 0 120 400 800 400 900", "payload: " + got;
	nmTeardown();
}

test "scrollTo on a native ScrollView reaches the native scroll view" {
	const handles: ScrollViewHandle[] = [];
	const app = (): NeonNode => <ScrollView ref={(h: ScrollViewHandle): void => { handles.push(h); }}>
		<View style={{ height: 900 }} />
	</ScrollView>;
	runApp(app);
	handles[0].scrollTo({ y: 120, animated: false });
	assert `${nmScrolledX()} ${nmScrolledY()} ${nmScrolledAnimated()}` === "0 120 0", "scrolled " + `${nmScrolledX()} ${nmScrolledY()} ${nmScrolledAnimated()}`;
	nmTeardown();
}

test "onLayout reports a native view's frame after mount and again when a rotation changes it" {
	let got = "";
	const app = (): NeonNode => <View style={{ height: 100 }} onLayout={(e: NeonEvent): void => {
		got += `${e.type} ${e.x} ${e.y} ${e.width} ${e.height};`;
	}} />;
	runApp(app);
	assert got === "layout 0 0 400 100;", "after mount: " + got;
	nmResize(800, 400);
	assert got === "layout 0 0 400 100;layout 0 0 800 100;", "after a rotation: " + got;
	nmResize(800, 400);
	assert got === "layout 0 0 400 100;layout 0 0 800 100;", "an unchanged frame does not fire again: " + got;
	nmResize(400, 800);
	nmTeardown();
}

interface Entry {
	id: string;
	n: number;
}

function entries(count: number): Entry[] {
	const out: Entry[] = [];
	for (let i = 0; i < count; i += 1) { out.push({ id: "e" + i.toString(), n: i }); }
	return out;
}

function rowLayout(data: Entry[], index: number): ItemLayout {
	return { length: 50, offset: 50 * index, index };
}

// Parked: inline style literals on the generic FlatList lose their Style type —
// ~/metascript/.inbox/compiler/2026-10-03-object-literal-prop-of-a-generic-component-loses-its-contextual-type.md
const fill: Style = { flex: 1 };
const rowBox: Style = { height: 50 };

test "a 10000-row FlatList creates native views for its window only and sizes the content to every row" {
	const data = entries(10000);
	const before = nmViewsCreated();
	const app = (): NeonNode => <FlatList data={data} style={fill} keyExtractor={(e: Entry, i: number): string => e.id} getItemLayout={rowLayout}
		renderItem={(info: ListRenderItemInfo<Entry>): NeonNode => <View style={rowBox}><Text>{"row " + info.item.n.toString()}</Text></View>} />;
	runApp(app);
	const created = nmViewsCreated() - before;
	assert created > 100 && created < 1000, "views for the window, not 10000 rows: " + created.toString();
	assert nmContentHeight() === 500000, "content spans every row: " + nmContentHeight().toString();
	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "every window view is released";
}

test "an empty string node, such as a region's anchor, takes no layout space and no gap" {
	let got = "";
	const none: number[] = [];
	// Parked: an inline style literal in the For row fails on C —
	// ~/metascript/.inbox/compiler/2026-10-03-style-literal-in-a-for-row-assigns-int-to-a-union-on-c.md
	const app = (): NeonNode => <View style={{ gap: 10 }} onLayout={(e: NeonEvent): void => { got = `${e.height}`; }}>
		<View style={{ height: 20 }} />
		<For each={none}>{(n: number, i: Accessor<number>): NeonNode => <View style={rowBox} />}</For>
		<View style={{ height: 20 }} />
	</View>;
	runApp(app);
	assert got === "50", "two 20-high boxes and one gap: " + got;
	nmTeardown();
}

test "one native scroll event that moves a FlatList window runs one layout pass" {
	const data = entries(10000);
	const app = (): NeonNode => <FlatList data={data} style={fill} keyExtractor={(e: Entry, i: number): string => e.id} getItemLayout={rowLayout}
		renderItem={(info: ListRenderItemInfo<Entry>): NeonNode => <View style={rowBox}><Text>{"row " + info.item.n.toString()}</Text></View>} />;
	runApp(app);
	const before = nmScreenHeightReads();
	nmScroll(nmLastScrollTag(), 0, 1000, 400, 800, 400, 500000);
	const passes = nmScreenHeightReads() - before;
	nmTeardown();
	assert passes === 1, "layout passes for one scroll event: " + passes.toString();
}

test "a layout pass that leaves a ScrollView's frame and content size alone writes neither to the native scroll view" {
	const [y, setY] = createSignal<number>(0);
	const app = (): NeonNode => <View style={{ flex: 1 }}>
		<Text>{"offset " + y().toString()}</Text>
		<ScrollView style={{ flex: 1 }} onScroll={(e: NeonEvent): void => { setY(e.y); }}>
			<View style={{ height: 900 }} />
		</ScrollView>
	</View>;
	runApp(app);
	const frames = nmScrollFrameWrites();
	const sizes = nmContentSizeWrites();
	const passes = nmScreenHeightReads();
	nmScroll(nmLastScrollTag(), 0, 120, 400, 760, 400, 900);
	const ran = nmScreenHeightReads() - passes;
	const framed = nmScrollFrameWrites() - frames;
	const sized = nmContentSizeWrites() - sizes;
	nmTeardown();
	assert ran === 1, "the changed offset text runs a layout pass: " + ran.toString();
	assert framed === 0, "frame writes to the unchanged scroll view: " + framed.toString();
	assert sized === 0, "content size writes for unchanged content: " + sized.toString();
}
