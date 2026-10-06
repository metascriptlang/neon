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
	nmScrollFrameWrites, nmScreenHeightReads, nmDrag, nmPull, nmLoop,
	nmTransformWrites, nmVisualX, nmVisualY, nmLayoutWidth, nmLayoutHeight, nmTouchAt, nmLastPressableTag,
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

const rowBox: Style = { height: 50 };

function loopUntilIdle(): void {
	for (let i = 0; i < 1000 && nmLoop() === 0; i += 1) {}
}

test "a 10000-row FlatList creates native views for its window only and sizes the content to every row" {
	const data = entries(10000);
	const before = nmViewsCreated();
	const app = (): NeonNode => <FlatList data={data} style={{ flex: 1 }} getItemLayout={rowLayout} updateCellsBatchingPeriod={0}
		renderItem={(info: ListRenderItemInfo<Entry>): NeonNode => <View style={rowBox}><Text>{"row " + info.item.n.toString()}</Text></View>} />;
	runApp(app);
	loopUntilIdle();
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
	const app = (): NeonNode => <FlatList data={data} style={{ flex: 1 }} getItemLayout={rowLayout} updateCellsBatchingPeriod={0}
		renderItem={(info: ListRenderItemInfo<Entry>): NeonNode => <View style={rowBox}><Text>{"row " + info.item.n.toString()}</Text></View>} />;
	runApp(app);
	loopUntilIdle();
	const views = nmViewsCreated();
	const before = nmScreenHeightReads();
	nmScroll(nmLastScrollTag(), 0, 100000, 400, 800, 400, 500000);
	const passes = nmScreenHeightReads() - before;
	const moved = nmViewsCreated() > views;
	nmTeardown();
	assert moved && passes === 1, "layout passes for one scroll event that moves the window: " + passes.toString();
}

function tallness(n: number): Style {
	return { height: 30 + (n % 4) * 10 };
}

test "a FlatList without getItemLayout measures its native rows and scrolls to its end through them" {
	const data = entries(1000);
	const before = nmViewsCreated();
	const app = (): NeonNode => <FlatList data={data} style={{ flex: 1 }} windowSize={3} updateCellsBatchingPeriod={0}
		renderItem={(info: ListRenderItemInfo<Entry>): NeonNode => <View style={tallness(info.item.n)}><Text>{"row " + info.item.n.toString()}</Text></View>} />;
	runApp(app);
	loopUntilIdle();
	const full = 250 * (30 + 40 + 50 + 60);
	const window = nmViewsCreated() - before;
	assert window > 20 && window < 600, "views for a measured window: " + window.toString();
	assert nmContentHeight() < full, "the content stops at the measured rows: " + nmContentHeight().toString();
	let steps = 0;
	while (nmContentHeight() < full && steps < 500) {
		nmScroll(nmLastScrollTag(), 0, nmContentHeight() - 800, 400, 800, 400, nmContentHeight());
		loopUntilIdle();
		steps += 1;
	}
	const live = nmViewsCreated() - nmReleaseCalls();
	nmTeardown();
	assert nmContentHeight() === full, "every row measured at its own height after " + steps.toString() + " scrolls: " + nmContentHeight().toString();
	assert live < 600, "still a window at the end: " + live.toString();
}

test "a FlatList batch that a std timer runs is laid out once per pass of the UI loop" {
	const data = entries(10000);
	const app = (): NeonNode => <FlatList data={data} style={{ flex: 1 }} getItemLayout={rowLayout} updateCellsBatchingPeriod={0}
		renderItem={(info: ListRenderItemInfo<Entry>): NeonNode => <View style={rowBox}><Text>{"row " + info.item.n.toString()}</Text></View>} />;
	runApp(app);
	let worst = 0;
	let batches = 0;
	for (let i = 0; i < 1000; i += 1) {
		const views = nmViewsCreated();
		const before = nmScreenHeightReads();
		const next = nmLoop();
		if (nmViewsCreated() > views) { batches += 1; }
		worst = Math.max(worst, nmScreenHeightReads() - before);
		if (next !== 0) { break; }
	}
	nmTeardown();
	assert batches > 0 && worst === 1, `${batches} batches, at most ${worst} layout passes in one pass of the loop`;
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

test "a ScrollView with no style fits its parent instead of growing to its content, React Native's base style" {
	let got = "";
	const app = (): NeonNode => <ScrollView onLayout={(e: NeonEvent): void => { got = `${e.height}`; }}>
		<View style={{ height: 2000 }} />
	</ScrollView>;
	runApp(app);
	nmTeardown();
	assert got === "800", "the scroll view's height in an 800-high screen: " + got;
}

test "horizontal content measures on the x axis" {
	const app = (): NeonNode => <ScrollView horizontal={true}>
		<View style={{ width: 300, height: 100 }} />
		<View style={{ width: 300, height: 100 }} />
		<View style={{ width: 300, height: 100 }} />
	</ScrollView>;
	runApp(app);
	assert nmContentWidth() === 900, "three 300-wide children share one horizontal row";
	nmTeardown();
}


test "native Style transforms paint and hit-test around the centre without changing layout, and reset on none or null" {
	const [transform, setTransform] = createSignal<string | null>("scaleX(-1) translateX(10px) scaleY(-1)");
	let layouts: int32 = 0;
	let pressed: int32 = 0;
	const app = (): NeonNode => <Pressable style={{ width: 100, height: 40, transform: transform() }}
		onLayout={(e: NeonEvent): void => {
			assert e.width === 100 && e.height === 40, "layout is independent of paint";
			layouts += 1;
		}}
		onPress={() => { pressed += 1; }} />;
	runApp(app);
	const tag = nmLastPressableTag();
	assert nmVisualX(tag, 0) === 90 && nmVisualX(tag, 100) === -10, "inversion scales the subsequent x translation";
	assert nmVisualY(tag, 0) === 40 && nmVisualY(tag, 40) === 0, "vertical inversion is centred on the view";
	nmTouchAt(40, 20, PRESS);
	assert pressed === 1, "a transformed hit still routes to the pressable";
	const writes = nmTransformWrites();
	setTransform("translateX(15px) scale(2, 3)");
	assert nmVisualX(tag, 0) === -35 && nmVisualX(tag, 100) === 165, "translation before scale is not multiplied";
	assert nmVisualY(tag, 0) === -40 && nmVisualY(tag, 40) === 80, "nonuniform scale uses the unchanged layout height";
	assert nmTransformWrites() === writes + 1, "one update projects one transform";
	setTransform("none");
	assert nmVisualX(tag, 0) === 0 && nmVisualY(tag, 0) === 0, "none clears scale and translation";
	setTransform("translate(12px, 7px)");
	assert nmVisualX(tag, 0) === 12 && nmVisualY(tag, 0) === 7, "sticky-style translation paints without moving the layout frame";
	setTransform(null);
	assert nmVisualX(tag, 0) === 0 && nmVisualY(tag, 0) === 0, "null also clears a prior transform";
	assert nmLayoutWidth(tag) === 100 && nmLayoutHeight(tag) === 40 && layouts === 1, "paint updates neither resize nor repeat onLayout";
	nmTeardown();
}

test "inverted native scroll content keeps logical offsets and frames after resizing, with double-inverted rows still pressable" {
	let pressed = false;
	let payload = "";
	const handles: ScrollViewHandle[] = [];
	const app = (): NeonNode => <ScrollView style={{ flexGrow: 0, flexShrink: 0, height: 100, transform: "scaleY(-1)" }}
		ref={(h: ScrollViewHandle): void => { handles.push(h); }}
		onScroll={(e: NeonEvent): void => { payload = `${e.y} ${e.height} ${e.contentHeight}`; }}>
		<View style={{ height: 200 }} />
		<Pressable style={{ width: 100, height: 50, transform: "scaleY(-1)" }}
			onPress={() => { pressed = true; }} />
	</ScrollView>;
	runApp(app);
	const tag = nmLastPressableTag();
	const scrollTag = nmLastScrollTag();
	assert nmLayoutHeight(scrollTag) === 100, "the fixture declares a fixed viewport instead of flex-growing";
	assert nmContentHeight() === 250, "paint inversion does not change content coordinates";
	handles[0].scrollTo({ y: 150, animated: false });
	assert nmScrolledY() === 150, "imperative offsets remain untransformed";
	nmScroll(scrollTag, 0, 150, 400, 100, 400, 250);
	assert payload === "150 100 250", "scroll event metrics remain untransformed";
	assert nmVisualY(tag, 0) === 0 && nmVisualY(tag, 50) === 50, "two inversions restore the visible row direction at the logical offset";
	nmTouchAt(50, 25, PRESS);
	assert pressed, "transformed content routes the visible row's touch";
	const transforms = nmTransformWrites();
	nmResize(800, 400);
	assert nmLayoutWidth(scrollTag) === 800 && nmLayoutHeight(scrollTag) === 100, "an inverted viewport still receives the new logical frame";
	assert nmVisualY(tag, 0) === 0 && nmVisualY(tag, 50) === 50, "resizing preserves the scroll offset and existing transform";
	assert nmContentHeight() === 250 && nmTransformWrites() === transforms, "layout does not re-project or reparse transforms";
	nmResize(400, 800);
	nmTeardown();
}

test "unrelated native Style changes keep the cached transform projection" {
	const [height, setHeight] = createSignal<number>(40);
	const app = (): NeonNode => <Pressable style={{ width: 100, height: height(), transform: "scaleX(-1)" }}
		onPress={() => {}} />;
	runApp(app);
	const tag = nmLastPressableTag();
	const writes = nmTransformWrites();
	setHeight(60);
	assert nmLayoutHeight(tag) === 60 && nmVisualX(tag, 0) === 100, "new layout with the old inversion";
	assert nmTransformWrites() === writes, "the same CSS transform is not parsed or projected again";
	nmTeardown();
}
