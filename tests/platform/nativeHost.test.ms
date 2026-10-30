import { runApp, createNativeHost } from "../../src/platform/native/host";
import "../../src/platform/native/switch";
import "../../src/platform/native/activityIndicator";
import "../../src/platform/native/modal";
import "../../src/platform/native/inputAccessoryView";
import { inputAccessoryViewNode } from "../../src/components/inputAccessoryView";
import { createSignal, Accessor, accessor } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { For, Errored } from "../../src/macros/ui/flow";
import { createRenderEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { onCleanup } from "../../src/core/cleanup";
import { Host, HostNode } from "../../src/render/hostTypes";
import { View, Pressable, ScrollView, ScrollViewHandle, TextInput, TextInputHandle, MaintainVisibleContentPosition } from "../../src/components/primitives";
import { element } from "../../src/macros/ui/element";
import { Switch } from "../../src/components/switch";
import { TouchableHighlight } from "../../src/components/touchable";
import { StatusBar } from "../../src/components/statusBar";
import { Modal } from "../../src/components/modal";
import { GalleryApp } from "../../examples/components/gallery";
import { KeyboardAvoidingView } from "../../src/components/keyboardAvoidingView";
import { ActivityIndicator } from "../../src/components/activityIndicator";
import { Image } from "../../src/components/image";
import { useColorScheme, useKeyboard, useWindowDimensions } from "../../src/render/environment";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { AccessibilityInfo } from "../../src/api/accessibilityInfo";
import { Text } from "../../src/components/primitives";
import { FlatList, FlatListHandle, ItemLayout, ListRenderItemInfo } from "../../src/components/flatList";

import {
	nmViewsCreated, nmReleaseCalls, nmTouch, nmTap, nmTeardown, nmMount, nmResize, nmScroll, nmLastScrollTag,
	nmContentWidth, nmContentHeight, nmScrolledX, nmScrolledY, nmScrolledAnimated, nmContentSizeWrites,
	nmScrollFrameWrites, nmScreenHeightReads, nmLoop,
	nmTransformWrites, nmVisualX, nmVisualY, nmLayoutWidth, nmLayoutHeight, nmTapAt, nmLastPressableTag,
	nmLayoutX, nmLayoutY, nmRestackWrites, nmAddChildWrites, nmDetachWrites, nmPaintTag, nmPaintTextIndex,
	nmControl, nmControlSized, nmTextWidth, nmTextHeight, nmLastControlTag, nmEnvironment, nmLastInputTag, nmFocused, nmAccessibilityFocusCalls, nmProp,
	nmTextVisualX, nmTextVisualY, nmScrollOffsetX, nmScrollOffsetY, nmScrollShifts,
	nmBackgroundAlpha, nmLastViewTag, nmAnyProp, nmTagWithProp, nmHasLabel,
	nmTouchFull, nmResponderTag, nmResponderBlocks, nmOpacity,
} from "./nativeBridgeMock.h";
import { PanResponder, PanResponderGestureState } from "../../src/components/panResponder";
import { HOST_PARK_CONTRACT, hostParkContract } from "../render/hostContract";
import { devDriver } from "../../src/devtools/driver";
import { ControlSession, handleRequest } from "../../src/devtools/control";

import { sleepAsync } from "std/core/promise";

const PRESS: int32 = 2;

test "the native host keeps the park contract and release frees the parked views" {
	const host = createNativeHost().host;
	const got = hostParkContract(host);
	assert got === HOST_PARK_CONTRACT, got;

	const created = nmViewsCreated();
	const released = nmReleaseCalls();
	const holder = host.createElement("view");
	const parked = host.createElement("view");
	host.append(parked, host.createElement("view"));
	host.insertBefore(holder, parked, null);
	assert nmViewsCreated() - created === 3, "the holder, the parked node and its child are three views";
	assert nmReleaseCalls() === released, "parking releases nothing";
	host.release(holder);
	assert nmReleaseCalls() - released === 3, "release frees the parked subtree with the holder: " + (nmReleaseCalls() - released).toString();
}

test "the app's body runs under the mounted root: its cleanups and effects belong to the app" {
	const [count, setCount] = createSignal<number>(0);
	let log = "";
	const app = (): NeonNode => {
		log += "body;";
		onCleanup((): void => { log += "cleanup;"; });
		createRenderEffect((prev: number | null): number => count(), (value: number, prev: number | null): Cleanup | null => { log += "seen " + value.toString() + ";"; return null; });
		return <View />;
	};
	runApp(app);
	setCount(1);
	flush();
	nmTeardown();
	setCount(2);
	flush();
	assert log === "body;seen 0;seen 1;cleanup;", log;
	nmMount();
	nmTeardown();
	assert log === "body;seen 0;seen 1;cleanup;body;seen 2;cleanup;", log;
}

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
	nmTap(2);
	assert pressed === "2;", "the second row's tag routes before removal: " + pressed;

	setRows([1, 3]);
	flush();
	assert nmViewsCreated() === created, "keyed rows 1 and 3 are not recreated";
	assert nmReleaseCalls() - released === 2, "the removed row releases its pressable and its label: " + (nmReleaseCalls() - released).toString();
	nmTap(2);
	nmTap(1);
	nmTap(3);
	assert pressed === "2;1;3;", "the removed tag is inert, the others still route: " + pressed;

	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "every created view is released after teardown";
	nmTap(1);
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
	const app = (): NeonNode => <View style={{ gap: 10 }} onLayout={(e: NeonEvent): void => { got = `${e.height}`; }}>
		<View style={{ height: 20 }} />
		<For each={none}>{(n: number, i: Accessor<number>): NeonNode => <View style={{ height: 20 }} />}</For>
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
	nmLoop();
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
	nmTapAt(40, 20);
	assert pressed === 1, "a transformed hit still routes to the pressable";
	const writes = nmTransformWrites();
	setTransform("translateX(15px) scale(2, 3)");
	flush();
	assert nmVisualX(tag, 0) === -35 && nmVisualX(tag, 100) === 165, "translation before scale is not multiplied";
	assert nmVisualY(tag, 0) === -40 && nmVisualY(tag, 40) === 80, "nonuniform scale uses the unchanged layout height";
	assert nmTransformWrites() === writes + 1, "one update projects one transform";
	setTransform("none");
	flush();
	assert nmVisualX(tag, 0) === 0 && nmVisualY(tag, 0) === 0, "none clears scale and translation";
	setTransform("translate(12px, 7px)");
	flush();
	assert nmVisualX(tag, 0) === 12 && nmVisualY(tag, 0) === 7, "sticky-style translation paints without moving the layout frame";
	setTransform(null);
	flush();
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
	nmTapAt(50, 25);
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
	flush();
	assert nmLayoutHeight(tag) === 60 && nmVisualX(tag, 0) === 100, "new layout with the old inversion";
	assert nmTransformWrites() === writes, "the same CSS transform is not parsed or projected again";
	nmTeardown();
}

test "native zIndex controls overlapping pressables without changing layout or detaching their views" {
	const [z, setZ] = createSignal<number | null>(10);
	const [color, setColor] = createSignal<string>("#112233");
	let pressed = "";
	let layouts: int32 = 0;
	const app = (): NeonNode => <View style={{ height: 100 }} onLayout={(e: NeonEvent): void => {}}>
		<Pressable style={{ width: 100, height: 40, zIndex: z(), backgroundColor: color() }}
			onLayout={(e: NeonEvent): void => { layouts += 1; }}
			onPress={() => { pressed += "upper;"; }} />
		<Pressable style={{ width: 100, height: 40, transform: "translateY(-40px)" }}
			onLayout={(e: NeonEvent): void => { layouts += 1; }}
			onPress={() => { pressed += "lower;"; }} />
	</View>;
	runApp(app);
	const parentTag = nmPaintTag(0, 0);
	const upperTag = nmPaintTag(parentTag, 1);
	const lowerTag = nmLastPressableTag();
	assert upperTag !== lowerTag, "the earlier high-z sibling paints last";
	assert nmLayoutY(upperTag) === 0 && nmLayoutY(lowerTag) === 40, "Yoga still uses logical child order";
	const added = nmAddChildWrites();
	const detached = nmDetachWrites();
	nmTapAt(50, 20);
	setZ(-1);
	flush();
	nmTapAt(50, 20);
	setZ(null);
	flush();
	nmTapAt(50, 20);
	setZ(10);
	flush();
	nmTapAt(50, 20);
	assert pressed === "upper;lower;lower;upper;", "touch order follows changed z, including a reset to equal zero: " + pressed;
	assert nmLayoutX(upperTag) === 0 && nmLayoutY(upperTag) === 0 &&
		nmLayoutY(lowerTag) === 40 && nmLayoutWidth(upperTag) === 100 && nmLayoutHeight(upperTag) === 40,
		"z changes leave logical frames alone";
	assert layouts === 2, "paint-order changes do not repeat onLayout";
	assert nmAddChildWrites() === added && nmDetachWrites() === detached, "restacking never removes or re-adds a view";
	const restacked = nmRestackWrites();
	setColor("#445566");
	flush();
	nmResize(400, 800);
	nmResize(800, 400);
	nmResize(400, 800);
	assert nmRestackWrites() === restacked, "unrelated Style updates and stable or resized layouts do not restack";
	nmTapAt(50, 20);
	assert pressed === "upper;lower;lower;upper;upper;", "the same press route survives paint and layout changes";
	nmTeardown();
}

test "native equal-z reorders preserve logical siblings and press state, with a cheap zero-z append path" {
	const levels: number[] = [0, 10];
	for (const level of levels) {
		const native = createNativeHost();
		const host = native.host;
		const p = host.createElement("View");
		host.setStyle(p, { width: 100, height: 100 });
		host.addEvent(p, "onLayout", (e: NeonEvent): void => {});
		host.append(native.rootNode, p);
		const parentTag = nmPaintTag(0, 0);
		let pressed = "";
		const a = host.createElement("View");
		const b = host.createElement("View");
		const c = host.createElement("View");
		const box: Style = { position: "absolute", top: 0, left: 0, width: 100, height: 40, zIndex: level };
		host.setStyle(a, box);
		host.setStyle(b, box);
		host.setStyle(c, box);
		host.addEvent(a, "onPress", (e: NeonEvent): void => { pressed += "a;"; });
		const aTag = nmLastPressableTag();
		host.addEvent(b, "onPress", (e: NeonEvent): void => { pressed += "b;"; });
		const bTag = nmLastPressableTag();
		host.addEvent(c, "onPress", (e: NeonEvent): void => { pressed += "c;"; });
		const cTag = nmLastPressableTag();
		const initialRestacks = nmRestackWrites();
		host.append(p, a);
		host.append(p, b);
		host.append(p, c);
		if (level === 0) { assert nmRestackWrites() === initialRestacks, "ordinary zero-z appends require no restack"; }
		nmTapAt(50, 20);
		const added = nmAddChildWrites();
		const detached = nmDetachWrites();
		host.insertBefore(p, a, c);
		assert host.firstChild(p) === b && host.nextSibling(b) === a && host.nextSibling(a) === c,
			"moving an earlier node forward adjusts the insertion index after unlinking it";
		assert nmPaintTag(parentTag, 0) === bTag && nmPaintTag(parentTag, 1) === aTag && nmPaintTag(parentTag, 2) === cTag,
			"equal z preserves the new logical order";
		host.insertBefore(p, c, b);
		nmTapAt(50, 20);
		assert host.firstChild(p) === c && host.nextSibling(c) === b && host.nextSibling(b) === a, "paint sorting never mutates Yoga children";
		host.insertBefore(p, c, null);
		nmTapAt(50, 20);
		host.append(p, b);
		nmTapAt(50, 20);
		assert pressed === "c;a;c;b;", "same views keep their press routes through insert and append moves: " + pressed;
		assert nmAddChildWrites() === added && nmDetachWrites() === detached, "same-parent moves only bring views forward";
		const restacked = nmRestackWrites();
		host.insertBefore(p, c, b);
		host.insertBefore(p, b, null);
		host.insertBefore(p, a, a);
		host.append(p, b);
		native.relayout();
		native.relayout();
		assert nmRestackWrites() === restacked, "no-op child moves and unchanged layout do not restack";
		host.removeChild(p, b);
		nmTapAt(50, 20);
		nmTap(bTag);
		assert pressed === "c;a;c;b;c;", "a removed upper sibling and its event route cannot take a hit";
		assert nmPaintTag(parentTag, 0) === aTag && nmPaintTag(parentTag, 1) === cTag, "removal preserves the remaining paint order";
		const q = host.createElement("View");
		host.setStyle(q, { position: "absolute", top: 0, left: 0, width: 100, height: 100 });
		host.addEvent(q, "onLayout", (e: NeonEvent): void => {});
		host.append(native.rootNode, q);
		const nextParentTag = nmPaintTag(0, 1);
		const d = host.createElement("View");
		host.setStyle(d, { position: "absolute", top: 0, left: 0, width: 100, height: 40 });
		host.addEvent(d, "onPress", (e: NeonEvent): void => { pressed += "d;"; });
		const dTag = nmLastPressableTag();
		host.append(q, d);
		const beforeMove = nmDetachWrites();
		host.append(q, c);
		assert nmDetachWrites() === beforeMove + 1, "only a real reparent detaches the moved view";
		assert host.firstChild(p) === a && host.nextSibling(a) === null && host.firstChild(q) === d && host.nextSibling(d) === c,
			"reparenting updates logical child lists";
		assert nmPaintTag(parentTag, 0) === aTag && nmPaintTag(nextParentTag, 1) === cTag, "no stale paint entry remains in the old parent";
		nmTapAt(50, 20);
		host.setStyle(c, { position: "absolute", top: 0, left: 0, width: 100, height: 40, zIndex: -1 });
		assert nmPaintTag(nextParentTag, 0) === cTag && nmPaintTag(nextParentTag, 1) === dTag, "the new parent responds to the moved child's z change";
		nmTapAt(50, 20);
		assert pressed === "c;a;c;b;c;c;d;", "reparented routes remain live and respect their new siblings: " + pressed;
		host.removeChild(native.rootNode, q);
		host.removeChild(native.rootNode, p);
		assert nmReleaseCalls() === nmViewsCreated(), "every moved or removed view is released exactly once";
		nmTeardown();
	}
}

test "native percent dimensions lay out against the parent" {
	const app = (): NeonNode => <View style={{ width: 200, height: 100 }}>
		<Pressable style={{ width: "50%", height: "100%", maxHeight: "40%" }} onPress={() => {}} />
	</View>;
	runApp(app);
	const tag = nmLastPressableTag();
	assert nmLayoutWidth(tag) === 100 && nmLayoutHeight(tag) === 40, `percent sizes resolve against the 200x100 parent: ${nmLayoutWidth(tag)}x${nmLayoutHeight(tag)}`;
	nmTeardown();
}

test "native materialized string labels participate in paint order and reuse their views when moved" {
	const native = createNativeHost();
	const host = native.host;
	const p = host.createElement("View");
	host.setStyle(p, { width: 100, height: 100 });
	host.addEvent(p, "onLayout", (e: NeonEvent): void => {});
	host.append(native.rootNode, p);
	const parentTag = nmPaintTag(0, 0);
	const label = host.createText("label");
	const upper = host.createElement("View");
	host.setStyle(upper, { height: 40, zIndex: 10 });
	host.addEvent(upper, "onPress", (e: NeonEvent): void => {});
	const upperTag = nmLastPressableTag();
	host.append(p, upper);
	host.append(p, label);
	assert nmPaintTextIndex(parentTag, "label") === 0 && nmPaintTag(parentTag, 1) === upperTag,
		"materialized labels are zero-z children, not excluded from restacking";
	host.setStyle(upper, { height: 40 });
	assert nmPaintTextIndex(parentTag, "label") === 1, "resetting the only nonzero z restores logical order";
	const created = nmViewsCreated();
	const detached = nmDetachWrites();
	host.insertBefore(p, label, upper);
	assert nmViewsCreated() === created && nmDetachWrites() === detached && nmPaintTextIndex(parentTag, "label") === 0,
		"same-parent string moves restack the existing label without recreating or detaching it";
	host.append(p, label);
	assert nmPaintTextIndex(parentTag, "label") === 1, "string appends also follow logical equal-z order";
	const q = host.createElement("View");
	host.addEvent(q, "onLayout", (e: NeonEvent): void => {});
	host.append(native.rootNode, q);
	const nextParentTag = nmPaintTag(0, 1);
	host.insertBefore(q, label, null);
	assert nmViewsCreated() === created + 1 && nmPaintTextIndex(parentTag, "label") === -1 && nmPaintTextIndex(nextParentTag, "label") === 0,
		"moving a materialized label to another view reuses it and removes it from its old paint order";
	const text = host.createElement("text");
	host.append(native.rootNode, text);
	let refused = "";
	try { host.append(text, label); } catch (e) { refused = e.toString(); }
	assert refused.indexOf("arrives through its paragraph") >= 0, "a string is not appended into a Text: " + refused;
	assert nmPaintTextIndex(nextParentTag, "label") === 0, "the refused move leaves the label where it was";
	host.removeChild(q, label);
	assert nmPaintTextIndex(nextParentTag, "label") === -1, "removed labels cannot remain in paint order";
	host.removeChild(native.rootNode, text);
	host.removeChild(native.rootNode, q);
	host.removeChild(native.rootNode, p);
	assert nmReleaseCalls() === nmViewsCreated(), "string materialization and cleanup leave no native views behind";
	nmTeardown();
}

test "a native sticky list paints and routes its retained header above rows, then removes and changes its sticky indices" {
	const data = entries(40);
	const [indices, setIndices] = createSignal<int32[]>([0, 5, 10, 15, 20, 25, 30, 35]);
	const handles: FlatListHandle[] = [];
	let pressed = "";
	const app = (): NeonNode => <FlatList data={data} getItemLayout={rowLayout}
		style={{ height: 200, flexGrow: 0, flexShrink: 0 }} windowSize={1} initialNumToRender={1}
		updateCellsBatchingPeriod={0} stickyHeaderIndices={indices()} ref={(h: FlatListHandle): void => { handles.push(h); }}
		renderItem={(info: ListRenderItemInfo<Entry>): NeonNode => <Pressable style={rowBox} onPress={() => { pressed += info.item.n.toString() + ";"; }}><Text>{info.item.id}</Text></Pressable>} />;
	runApp(app);
	loopUntilIdle();
	const scrollTag = nmLastScrollTag();
	handles[0].scrollToOffset({ offset: 650, animated: false });
	nmScroll(scrollTag, 0, 650, 400, 200, 400, 2000);
	loopUntilIdle();
	nmTapAt(50, 25);
	assert pressed === "10;", "the preceding sticky header receives the overlapping row's press: " + pressed;
	setIndices([]);
	flush();
	loopUntilIdle();
	nmTapAt(50, 25);
	assert pressed === "10;13;", "removing sticky indices exposes the ordinary visible row: " + pressed;
	setIndices([0, 13]);
	flush();
	handles[0].scrollToOffset({ offset: 700, animated: false });
	nmScroll(scrollTag, 0, 700, 400, 200, 400, 2000);
	loopUntilIdle();
	nmTapAt(50, 25);
	assert pressed === "10;13;13;", "changing indices makes the retained row stick instead: " + pressed;
	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "sticky wrappers leave no native view behind";
}

function prop(tag: int32, name: string): string {
	return nmProp(tag, name);
}

test "AccessibilityInfo.setAccessibilityFocus reaches the native view while it is mounted" {
	const handles: TextInputHandle[] = [];
	const [shown, setShown] = createSignal(true);
	runApp((): NeonNode => <View>
		{shown() ? <TextInput ref={(h: TextInputHandle): void => { handles.push(h); }} /> : null}
	</View>);
	const before = nmAccessibilityFocusCalls();
	AccessibilityInfo.setAccessibilityFocus(handles[0]);
	assert nmAccessibilityFocusCalls() === before + 1, "the call reached the bridge with that view";
	setShown(false);
	flush();
	AccessibilityInfo.setAccessibilityFocus(handles[0]);
	assert nmAccessibilityFocusCalls() === before + 1, "an unmounted handle is ignored";
	nmTeardown();
}

test "a native TextInput writes its props, routes typing, focus and submit, and follows a controlled value" {
	const [name, setName] = createSignal("Ada");
	const handles: TextInputHandle[] = [];
	let log = "";
	const app = (): NeonNode => <View>
		<TextInput value={name()} placeholder="Name" returnKeyType="next" accessibilityLabel="Name field"
			ref={(h: TextInputHandle): void => { handles.push(h); }}
			onChangeText={(t: string): void => { log += "change " + t + ";"; setName(t.toUpperCase()); }}
			onFocus={(e: NeonEvent): void => { log += "focus;"; }}
			onBlur={(e: NeonEvent): void => { log += "blur;"; }}
			onSubmitEditing={(e: NeonEvent): void => { log += "submit " + e.value + ";"; }} />
	</View>;
	runApp(app);
	const tag = nmLastInputTag();
	assert prop(tag, "value") === "Ada", "initial value: " + prop(tag, "value");
	assert prop(tag, "placeholder") === "Name", "placeholder: " + prop(tag, "placeholder");
	assert prop(tag, "returnKeyType") === "next", "returnKeyType: " + prop(tag, "returnKeyType");
	assert prop(tag, "accessibilityLabel") === "Name field", "label: " + prop(tag, "accessibilityLabel");
	assert nmLayoutHeight(tag) === 21, "an input without a height takes its measured line height: " + nmLayoutHeight(tag).toString();
	handles[0].focus();
	assert nmFocused(tag) === 1 && handles[0].isFocused(), "focus() reaches the native field and isFocused follows it";
	nmControl(tag, 0, "grace");
	nmLoop();
	assert prop(tag, "value") === "GRACE", "the controlled value is written back: " + prop(tag, "value");
	nmControl(tag, 3, "GRACE");
	handles[0].blur();
	assert !handles[0].isFocused(), "blur() clears isFocused";
	assert log === "focus;change grace;submit GRACE;blur;", "event order: " + log;
	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "the input is released with the rest";
}

test "a native TextInput's key press reaches onKeyPress with its key" {
	let log = "";
	const app = (): NeonNode => <View>
		<TextInput value="" onKeyPress={(e: NeonEvent): void => { log += `key ${e.key} "${e.value}";`; }} />
	</View>;
	runApp(app);
	nmControl(nmLastInputTag(), 16, "Escape");
	assert log === "key Escape \"\";", "onKeyPress carries the key and no value: " + log;
	nmTeardown();
}

test "the native host publishes window size, keyboard height and color scheme as signals" {
	let seen = "";
	const dims = useWindowDimensions();
	const keyboard = useKeyboard();
	const scheme = useColorScheme();
	const app = (): NeonNode => <View>
		<Text>{`${dims().width}x${dims().height} ${keyboard().visible ? "kb " + keyboard().height.toString() : "no kb"} ${scheme()}`}</Text>
	</View>;
	runApp(app);
	seen = `${dims().width}x${dims().height} ${keyboard().height} ${scheme()}`;
	assert seen === "400x800 0 light", "initial environment: " + seen;
	nmEnvironment(300, 1);
	seen = `${dims().width}x${dims().height} ${keyboard().height} ${scheme()}`;
	assert seen === "400x800 300 dark", "keyboard and dark mode: " + seen;
	nmResize(800, 400);
	seen = `${dims().width}x${dims().height} ${keyboard().height} ${scheme()}`;
	assert seen === "800x400 300 dark", "rotation: " + seen;
	nmEnvironment(0, 0);
	nmResize(400, 800);
	nmTeardown();
}

test "native Switch, ActivityIndicator and Image write their props, size themselves and route their events" {
	const [on, setOn] = createSignal(false);
	const [busy, setBusy] = createSignal(true);
	let log = "";
	const app = (): NeonNode => <View>
		<Switch value={on()} onValueChange={(v: boolean): void => { log += `switch ${v};`; setOn(v); }} accessibilityLabel="Dark mode" />
		<ActivityIndicator animating={busy()} size="large" color="#ff0000" onLayout={(e: NeonEvent): void => {}} />
		<Image source={{ uri: "https://example.com/a.png" }} resizeMode="cover" style={{ width: 64, height: 48 }}
			onLoad={(e: NeonEvent): void => { log += `load ${e.width}x${e.height};`; }}
			onError={(e: NeonEvent): void => { log += `error ${e.value};`; }} />
	</View>;
	runApp(app);
	const toggle = nmLastControlTag(2);
	const spinner = nmLastControlTag(3);
	const picture = nmLastControlTag(4);
	assert prop(toggle, "value") === "false" && prop(toggle, "accessibilityLabel") === "Dark mode", "switch props";
	assert `${nmLayoutWidth(toggle)}x${nmLayoutHeight(toggle)}` === "51x31", "the switch takes its native size: " + `${nmLayoutWidth(toggle)}x${nmLayoutHeight(toggle)}`;
	assert prop(spinner, "animating") === "true" && prop(spinner, "color") === "#ff0000" && prop(spinner, "accessibilityRole") === "progressbar", "indicator props";
	assert `${nmLayoutWidth(spinner)}x${nmLayoutHeight(spinner)}` === "36x36", "large indicator: " + `${nmLayoutWidth(spinner)}x${nmLayoutHeight(spinner)}`;
	assert prop(picture, "source") === "https://example.com/a.png" && prop(picture, "resizeMode") === "cover", "image props";
	assert `${nmLayoutWidth(picture)}x${nmLayoutHeight(picture)}` === "64x48", "image frame";
	nmControl(toggle, 4, "true");
	nmLoop();
	assert prop(toggle, "value") === "true", "the controlled switch follows its signal";
	setBusy(false);
	flush();
	assert prop(spinner, "animating") === "false", "animating follows its signal";
	nmControlSized(picture, 5, "", 640, 480);
	nmControl(picture, 6, "HTTP 404");
	assert log === "switch true;load 640x480;error HTTP 404;", "events: " + log;
	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "controls are released";
}

test "native text wraps to the width its container gives it, so a row grows with a long description" {
	const long = "a long description that wraps onto several lines in a narrow column";
	const app = (): NeonNode => <View>
		<View style={{ flexDirection: "row", padding: 10 }}>
			<View style={{ width: 56, height: 56 }} />
			<View style={{ flex: 1, paddingLeft: 12 }}>
				<Text>{long}</Text>
			</View>
		</View>
	</View>;
	runApp(app);
	const size = `${nmTextWidth(long)}x${nmTextHeight(long)}`;
	assert size === "312x42", "the label takes the column's 312pt and wraps to two 21pt lines: " + size;
	nmResize(800, 400);
	const wide = `${nmTextWidth(long)}x${nmTextHeight(long)}`;
	assert wide === "570x21", "a wider window rewraps the same label: " + wide;
	nmResize(400, 800);
	nmTeardown();
}

test "a native FlatList that filters down to no rows shows its ListEmptyComponent" {
	const [rows, setRows] = createSignal<Entry[]>(entries(3));
	const app = (): NeonNode => <View style={{ flex: 1 }}>
		<FlatList data={rows()} style={{ flex: 1 }} updateCellsBatchingPeriod={0}
			ListEmptyComponent={<View style={{ padding: 32 }}><Text>nothing here</Text></View>}
			renderItem={(info: ListRenderItemInfo<Entry>): NeonNode => <View style={rowBox}><Text>{info.item.id}</Text></View>} />
	</View>;
	runApp(app);
	loopUntilIdle();
	setRows([]);
	flush();
	loopUntilIdle();
	assert nmTextHeight("nothing here") > 0, "the empty component has a frame: " + nmTextHeight("nothing here").toString();
	setRows(entries(2));
	flush();
	loopUntilIdle();
	nmTeardown();
}

test "a label that grows inside a shrink-wrapped box is remeasured unwrapped, not at the box's old width" {
	const [big, setBig] = createSignal(false);
	const app = (): NeonNode => <View style={{ flexDirection: "row" }}>
		<View style={{ padding: 16 }}>
			<Text style={{ fontSize: big() ? 20 : 17 }}>SAVE</Text>
		</View>
	</View>;
	runApp(app);
	assert `${nmTextWidth("SAVE")}x${nmTextHeight("SAVE")}` === "34x21", "initial: " + `${nmTextWidth("SAVE")}x${nmTextHeight("SAVE")}`;
	setBig(true);
	flush();
	assert `${nmTextWidth("SAVE")}x${nmTextHeight("SAVE")}` === "40x24", "a bigger font keeps one line: " + `${nmTextWidth("SAVE")}x${nmTextHeight("SAVE")}`;
	nmTeardown();
}

test "a native TextInput's padding reaches the native field as text insets" {
	const app = (): NeonNode => <View>
		<TextInput style={{ padding: 8, paddingLeft: 12, height: 44 }} onChangeText={(t: string): void => {}} />
	</View>;
	runApp(app);
	assert prop(nmLastInputTag(), "textInsets") === "12,8,8,8", "insets: " + prop(nmLastInputTag(), "textInsets");
	nmTeardown();
}

function numbers(first: number, count: number): number[] {
	const out: number[] = [];
	for (let i = 0; i < count; i += 1) { out.push(first + i); }
	return out;
}

function prepended(rows: number[], count: number): number[] {
	const out = numbers(rows[0] - count, count);
	for (const n of rows) { out.push(n); }
	return out;
}

function rowsOf(rows: () => number[]): NeonNode {
	return element(<For each={rows()}>{(n: number, i: Accessor<number>): NeonNode => <View style={{ height: 50 }}><Text>{"row " + n.toString()}</Text></View>}</For>);
}

function withLoader(load: () => void, body: NeonNode): NeonNode {
	return element(<View style={{ flex: 1 }}><Pressable onPress={(e: NeonEvent): void => { load(); }}><Text>load</Text></Pressable>{body}</View>);
}

function pressLoad(): void {
	nmTap(nmLastPressableTag());
	nmLoop();
}

function keptRows(rows: () => number[], keep: MaintainVisibleContentPosition | null, seen: (e: NeonEvent) => void): NeonNode {
	if (keep === null) {
		return element(<ScrollView style={{ height: 200, flexGrow: 0 }} onScroll={seen}>{rowsOf(rows)}</ScrollView>);
	}
	const position = keep as MaintainVisibleContentPosition;
	return element(<ScrollView style={{ height: 200, flexGrow: 0 }} maintainVisibleContentPosition={position} onScroll={seen}>{rowsOf(rows)}</ScrollView>);
}

test "a native ScrollView with maintainVisibleContentPosition keeps its first visible row still while rows are prepended above it" {
	const [rows, setRows] = createSignal<number[]>(numbers(0, 10));
	let reported = -1.0;
	runApp((): NeonNode => withLoader((): void => { setRows(prepended(rows(), 3)); },
		keptRows(rows, { minIndexForVisible: 0 }, (e: NeonEvent): void => { reported = e.y; })));
	const tag = nmLastScrollTag();
	nmScroll(tag, 0, 120, 400, 200, 400, 500);
	const before = nmTextVisualY("row 2");
	pressLoad();
	const after = nmTextVisualY("row 2");
	const offset = nmScrollOffsetY(tag);
	nmTeardown();
	assert after === before, `row 2, the first visible row, stays at ${before}: ${after}`;
	assert offset === 270, "the offset moves by the three 50-high rows: " + offset.toString();
	assert reported === 270, "the shift reaches onScroll like a platform scroll: " + reported.toString();
}

test "without maintainVisibleContentPosition a native ScrollView keeps its offset and the rows move" {
	const [rows, setRows] = createSignal<number[]>(numbers(0, 10));
	runApp((): NeonNode => withLoader((): void => { setRows(prepended(rows(), 3)); }, keptRows(rows, null, (e: NeonEvent): void => {})));
	const tag = nmLastScrollTag();
	nmScroll(tag, 0, 120, 400, 200, 400, 500);
	const before = nmTextVisualY("row 2");
	const shifts = nmScrollShifts();
	pressLoad();
	const after = nmTextVisualY("row 2");
	const offset = nmScrollOffsetY(tag);
	const shifted = nmScrollShifts() - shifts;
	nmTeardown();
	assert after === before + 150, `row 2 moves down by the prepended rows: ${before} -> ${after}`;
	assert offset === 120 && shifted === 0, `the offset stays: ${offset}, ${shifted} shifts`;
}

test "minIndexForVisible skips the children before it when the native host picks the row to keep" {
	const [rows, setRows] = createSignal<number[]>(numbers(0, 10));
	runApp((): NeonNode => withLoader((): void => { setRows(prepended(rows(), 2)); },
		<ScrollView style={{ height: 200, flexGrow: 0 }} maintainVisibleContentPosition={{ minIndexForVisible: 1 }} onScroll={(e: NeonEvent): void => {}}>
			<View style={{ height: 100 }}><Text>header</Text></View>
			{rowsOf(rows)}
		</ScrollView>));
	const tag = nmLastScrollTag();
	nmScroll(tag, 0, 50, 400, 200, 400, 600);
	const before = nmTextVisualY("row 0");
	pressLoad();
	const after = nmTextVisualY("row 0");
	const offset = nmScrollOffsetY(tag);
	nmTeardown();
	assert after === before && offset === 150, `the first row past the partly visible header stays: ${before} -> ${after}, offset ${offset}`;
}

test "autoscrollToTopThreshold animates to the start after the shift when the offset was within it" {
	const [rows, setRows] = createSignal<number[]>(numbers(0, 10));
	runApp((): NeonNode => withLoader((): void => { setRows(prepended(rows(), 2)); },
		keptRows(rows, { minIndexForVisible: 0, autoscrollToTopThreshold: 10 }, (e: NeonEvent): void => {})));
	const tag = nmLastScrollTag();
	nmScroll(tag, 0, 5, 400, 200, 400, 500);
	pressLoad();
	const near = `${nmScrollShifts() > 0} ${nmScrolledY()} ${nmScrolledAnimated()}`;
	nmScroll(tag, 0, 120, 400, 200, 400, 600);
	const shifts = nmScrollShifts();
	pressLoad();
	const far = nmScrollOffsetY(tag);
	const shifted = nmScrollShifts() - shifts;
	nmTeardown();
	assert near === "true 0 1", "shifted, then animated to the start: " + near;
	assert far === 220 && shifted === 1, `past the threshold the offset only shifts: ${far}, ${shifted} shifts`;
}

test "a horizontal native ScrollView keeps its first visible column on the x axis" {
	const [rows, setRows] = createSignal<number[]>(numbers(0, 10));
	runApp((): NeonNode => withLoader((): void => { setRows(prepended(rows(), 3)); },
		<ScrollView horizontal={true} style={{ width: 200 }} maintainVisibleContentPosition={{ minIndexForVisible: 0 }} onScroll={(e: NeonEvent): void => {}}>
			<For each={rows()}>{(n: number, i: Accessor<number>): NeonNode => <View style={{ width: 50 }}><Text>{"col " + n.toString()}</Text></View>}</For>
		</ScrollView>));
	const tag = nmLastScrollTag();
	nmScroll(tag, 120, 0, 200, 800, 500, 800);
	const before = nmTextVisualX("col 2");
	pressLoad();
	const after = nmTextVisualX("col 2");
	const offset = `${nmScrollOffsetX(tag)} ${nmScrollOffsetY(tag)}`;
	nmTeardown();
	assert after === before && offset === "270 0", `column 2 stays at ${before}: ${after}, offset ${offset}`;
}

test "a native FlatList with maintainVisibleContentPosition keeps the visible message still when a press loads older ones" {
	const [data, setData] = createSignal<Entry[]>(entries(100));
	let older = 0;
	const app = (): NeonNode => <View style={{ flex: 1 }}>
		<Pressable onPress={(): void => {
			older += 1;
			const next: Entry[] = [];
			for (let i = 0; i < 20; i += 1) { next.push({ id: "old" + older.toString() + "_" + i.toString(), n: 1000 * older + i }); }
			for (const entry of data()) { next.push(entry); }
			setData(next);
		}}><Text>load older</Text></Pressable>
		<FlatList data={data()} style={{ flex: 1 }} getItemLayout={rowLayout} updateCellsBatchingPeriod={0}
			maintainVisibleContentPosition={{ minIndexForVisible: 0 }}
			renderItem={(info: ListRenderItemInfo<Entry>): NeonNode => <View style={rowBox}><Text>{"row " + info.item.n.toString()}</Text></View>} />
	</View>;
	runApp(app);
	loopUntilIdle();
	const tag = nmLastScrollTag();
	nmScroll(tag, 0, 1000, 400, 779, 400, 5000);
	loopUntilIdle();
	const before = nmTextVisualY("row 20");
	nmTap(nmLastPressableTag());
	loopUntilIdle();
	const after = nmTextVisualY("row 20");
	const offset = nmScrollOffsetY(tag);
	const height = nmContentHeight();
	nmTeardown();
	assert after === before, `row 20 stays at ${before}: ${after}`;
	assert offset === 2000 && height === 6000, `the offset follows the 20 older rows: ${offset}, content ${height}`;
}

test "a native Pressable is one accessibility element by default, and accessible={false} opts out" {
	const app = (): NeonNode => <View>
		<Pressable onPress={(e: NeonEvent): void => {}}><Text>Open</Text></Pressable>
		<Pressable accessible={false} onPress={(e: NeonEvent): void => {}}><Text>Quiet</Text></Pressable>
	</View>;
	runApp(app);
	const quiet = nmLastPressableTag();
	assert prop(quiet, "accessible") === "false", "opted out: " + prop(quiet, "accessible");
	assert prop(quiet - 1, "accessible") === "true", "default: " + prop(quiet - 1, "accessible");
	nmTeardown();
}

test "a native View writes the RN accessibility props and routes onAccessibilityAction with the action name" {
	let log = "";
	const app = (): NeonNode => <View>
		<View accessible={true} role="button" accessibilityRole="adjustable" accessibilityLabel="Volume"
			accessibilityValue={{ min: 0, max: 10, now: 3, text: "loud, very" }}
			accessibilityElementsHidden={true} accessibilityViewIsModal={true}
			accessibilityActions={[{ name: "increment" }, { name: "reset", label: "Reset" }]}
			onAccessibilityAction={(e: NeonEvent): void => { log += `${e.value};`; }}>
			<Text>Vol</Text>
		</View>
	</View>;
	runApp(app);
	const tag = nmTagWithProp("accessibilityLabel", "Volume");
	assert prop(tag, "role") === "button" && prop(tag, "accessibilityRole") === "adjustable", "both role props reach the bridge, which lets role win";
	assert prop(tag, "accessibilityValue") === "0,10,3,loud, very", "value text last: " + prop(tag, "accessibilityValue");
	assert prop(tag, "accessibilityElementsHidden") === "true" && prop(tag, "accessibilityViewIsModal") === "true", "hidden and modal";
	assert prop(tag, "accessibilityActions") === "increment\nreset\tReset", "actions: " + prop(tag, "accessibilityActions");
	nmControl(tag, 15, "reset");
	nmControl(tag, 15, "increment");
	nmLoop();
	assert log === "reset;increment;", "the action name arrives in event.value: " + log;
	nmTeardown();
}

test "a native TouchableHighlight paints its underlay while pressed and clears it to transparent" {
	const app = (): NeonNode => <View>
		<TouchableHighlight underlayColor="#336699" onPress={(e: NeonEvent): void => {}}><Text>Row</Text></TouchableHighlight>
	</View>;
	runApp(app);
	const tag = nmLastViewTag();
	assert nmBackgroundAlpha(tag) === 0, "transparent at rest";
	nmTouch(tag, 0);
	nmLoop();
	assert nmBackgroundAlpha(tag) === 1, "the underlay paints on press in";
	nmTouch(tag, 3);
	nmTeardown();
}

function anyProp(name: string): string {
	return nmAnyProp(name);
}

test "a native StatusBar sends its bar style and visibility through the prop channel and takes no space" {
	const [hidden, setHidden] = createSignal(false);
	const app = (): NeonNode => <View>
		<StatusBar barStyle="light-content" hidden={hidden()} />
		<View style={{ height: 50 }} onLayout={(e: NeonEvent): void => {}} />
	</View>;
	runApp(app);
	assert anyProp("statusBarStyle") === "light-content" && anyProp("statusBarHidden") === "false", "applied";
	setHidden(true);
	flush();
	assert anyProp("statusBarHidden") === "true", "hidden follows its signal";
	assert nmLayoutY(nmLastViewTag()) === 0, "the status bar node takes no layout space";
	nmTeardown();
}

test "a native KeyboardAvoidingView pads by the keyboard the host publishes" {
	const app = (): NeonNode => <KeyboardAvoidingView behavior="padding" style={{ flex: 1 }}>
		<View style={{ flex: 1 }} />
		<TextInput placeholder="Message" style={{ height: 40 }} onLayout={(e: NeonEvent): void => {}} />
	</KeyboardAvoidingView>;
	runApp(app);
	const field = nmLastInputTag();
	assert nmLayoutY(field) === 760, "at the bottom: " + nmLayoutY(field).toString();
	nmEnvironment(300, 0);
	assert nmLayoutY(field) === 460, "above the keyboard: " + nmLayoutY(field).toString();
	nmEnvironment(0, 0);
	assert nmLayoutY(field) === 760, "back down";
	nmTeardown();
}

test "a native Modal fills the root above the app, takes the touches below it and routes the back request" {
	const [open, setOpen] = createSignal(false);
	let log = "";
	const app = (): NeonNode => <View style={{ flex: 1 }}>
		<Pressable style={{ height: 100 }} onPress={(e: NeonEvent): void => { log += "under;"; }}><Text>under</Text></Pressable>
		<Modal visible={open()} transparent={true} onRequestClose={(): void => { log += "close;"; setOpen(false); }}>
			<Pressable style={{ marginTop: 300, height: 50 }} onPress={(e: NeonEvent): void => { log += "inside;"; }}><Text>inside</Text></Pressable>
		</Modal>
	</View>;
	runApp(app);
	nmTapAt(10, 50);
	assert log === "under;", "no modal yet: " + log;
	setOpen(true);
	flush();
	const modal = nmLastControlTag(5);
	assert `${nmLayoutWidth(modal)}x${nmLayoutHeight(modal)}` === "400x800", "fills the root: " + `${nmLayoutWidth(modal)}x${nmLayoutHeight(modal)}`;
	assert nmPaintTag(0, 1) === modal, "paints above the app";
	nmTapAt(10, 50);
	assert log === "under;", "the modal takes the touch over the app: " + log;
	nmTapAt(10, 320);
	nmLoop();
	assert log === "under;inside;", "its own content presses: " + log;
	nmControl(modal, 7, "");
	nmLoop();
	assert log === "under;inside;close;", "back asks to close: " + log;
	nmTapAt(10, 50);
	assert log === "under;inside;close;under;", "closed: the app presses again: " + log;
	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "the modal layer is released";
}

test "a native InputAccessoryView lays its children out across the top of the root above the app and presses them" {
	let log = "";
	const tools = (): NeonNode => <Pressable accessibilityLabel="Done" style={{ height: 44 }} onPress={(e: NeonEvent): void => { log += "tool;"; }}><Text>Done</Text></Pressable>;
	const bar = inputAccessoryViewNode({ nativeID: accessor((): string => "bar"), backgroundColor: accessor((): string => "#eeeeee"), children: tools() });
	const app = (): NeonNode => <View style={{ flex: 1 }}>
		<TextInput inputAccessoryViewID="bar" style={{ height: 40 }} />
		<Pressable style={{ height: 100 }} onPress={(e: NeonEvent): void => { log += "under;"; }}><Text>under</Text></Pressable>
		{bar}
	</View>;
	runApp(app);
	assert anyProp("nativeID") === "bar", "the accessory carries its nativeID: " + anyProp("nativeID");
	assert anyProp("backgroundColor") === "#eeeeee", "and its backgroundColor: " + anyProp("backgroundColor");
	assert anyProp("inputAccessoryViewID") === "bar", "the input names it: " + anyProp("inputAccessoryViewID");
	const tool = nmTagWithProp("accessibilityLabel", "Done");
	assert `${nmLayoutWidth(tool)}x${nmLayoutHeight(tool)}` === "400x44", "full width: " + `${nmLayoutWidth(tool)}x${nmLayoutHeight(tool)}`;
	nmTapAt(10, 20);
	nmLoop();
	assert log === "tool;", "its child presses and the app below does not: " + log;
	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "the accessory views are released";
}

test "native numberOfLines caps a wrapping label's measured height, and 0 lifts the cap" {
	const [lines, setLines] = createSignal(1);
	const long = "a long description that wraps onto several lines in a narrow column";
	const app = (): NeonNode => <View style={{ width: 120 }}>
		<Text numberOfLines={lines()}>{long}</Text>
	</View>;
	runApp(app);
	assert nmTextHeight(long) === 21, "one line: " + nmTextHeight(long).toString();
	setLines(0);
	flush();
	assert nmTextHeight(long) > 21, "unlimited wraps: " + nmTextHeight(long).toString();
	nmTeardown();
}

test "a native multiline TextInput is created as the platform's text area and routes typing like the field" {
	let typed = "";
	const app = (): NeonNode => <View>
		<TextInput multiline={true} placeholder="Notes" style={{ height: 120 }} onChangeText={(t: string): void => { typed = t; }} />
	</View>;
	runApp(app);
	const tag = nmLastInputTag();
	assert prop(tag, "multiline") === "true" && prop(tag, "placeholder") === "Notes", "a text area";
	assert nmLayoutHeight(tag) === 120, "its own height";
	nmControl(tag, 0, "line one\nline two");
	assert typed === "line one\nline two", "typing routes: " + typed;
	nmTeardown();
}

test "the gallery app runs on the native host: button, modal over the app, status bar and keyboard screen" {
	runApp(GalleryApp);
	assert nmHasLabel("status: ready") === 1, "mounted";
	nmTap(nmTagWithProp("accessibilityLabel", "Press me"));
	nmLoop();
	assert nmHasLabel("status: button 1") === 1, "button";
	nmTap(nmTagWithProp("accessibilityLabel", "Open modal"));
	nmLoop();
	assert nmHasLabel("Modal content") === 1, "modal open";
	const modal = nmLastControlTag(5);
	nmControl(modal, 7, "");
	nmLoop();
	assert nmHasLabel("Modal content") === 0 && nmHasLabel("status: modal closed by request") === 1, "back closes the modal";
	nmTap(nmTagWithProp("accessibilityLabel", "Hide status bar"));
	nmLoop();
	assert anyProp("statusBarHidden") === "true", "bar hidden";
	nmTap(nmTagWithProp("accessibilityLabel", "Open keyboard screen"));
	nmLoop();
	assert nmHasLabel("keyboard hidden") === 1, "keyboard screen";
	nmEnvironment(300, 0);
	assert nmHasLabel("keyboard 300") === 1, "keyboard published";
	nmEnvironment(0, 0);
	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "every view released";
}

const DOWN: int32 = 0;
const UP: int32 = 1;
const MOVE: int32 = 4;

test "a native pan row takes a horizontal drag from the Pressable inside it and blocks native scrolling" {
	let log = "";
	const pan = PanResponder.create({
		onMoveShouldSetPanResponder: (e: NeonEvent, g: PanResponderGestureState): boolean => Math.abs(g.dx) > 10,
		onPanResponderGrant: (e: NeonEvent, g: PanResponderGestureState): void => { log += `grant ${g.x0};`; },
		onPanResponderMove: (e: NeonEvent, g: PanResponderGestureState): void => { log += `move ${g.dx};`; },
		onPanResponderRelease: (e: NeonEvent, g: PanResponderGestureState): void => { log += `release ${g.dx};`; },
	});
	const app = (): NeonNode => <ScrollView>
		<View {...pan.panHandlers} style={{ height: 60 }}>
			<Pressable onPress={(): void => { log += "press;"; }}><Text>mail</Text></Pressable>
		</View>
	</ScrollView>;
	runApp(app);
	const button = nmLastPressableTag();
	nmTouchFull(button, DOWN, 100, 30, 1000);
	nmTouchFull(button, MOVE, 104, 31, 1016);
	assert nmResponderTag() === button && nmResponderBlocks() === 0, "under the slop the Pressable is responder and leaves native scrolling alone";
	nmTouchFull(button, MOVE, 130, 31, 1032);
	const holder = nmResponderTag();
	const blocks = nmResponderBlocks();
	nmTouchFull(button, MOVE, 150, 31, 1048);
	nmTouchFull(button, UP, 150, 31, 1064);
	nmTouchFull(button, PRESS, 150, 31, 1064);
	const released = nmResponderTag();
	nmTouchFull(button, DOWN, 10, 30, 2000);
	nmTouchFull(button, UP, 10, 30, 2010);
	nmTouchFull(button, PRESS, 10, 30, 2010);
	nmTeardown();
	assert holder !== 0 && holder !== button && blocks === 1, `the row holds the touch and blocks: ${holder} ${blocks}`;
	assert released === 0, "the release clears the native responder";
	assert log === "grant 130;move 20;release 20;press;", "the swipe does not press, a later tap does: " + log;
}

test "a native view whose style drops its background and opacity goes back to clear and opaque" {
	const [lifted, setLifted] = createSignal(true);
	const app = (): NeonNode => <View>
		<Pressable onPress={(): void => {}} style={lifted() ? { backgroundColor: "#6c7086", opacity: 0.5 } : { height: 10 }}><Text>row</Text></Pressable>
	</View>;
	runApp(app);
	const tag = nmLastPressableTag();
	const liftedOpacity = nmOpacity(tag);
	const liftedAlpha = nmBackgroundAlpha(tag);
	setLifted(false);
	flush();
	const restingOpacity = nmOpacity(tag);
	const restingAlpha = nmBackgroundAlpha(tag);
	nmTeardown();
	assert liftedOpacity === 0.5 && liftedAlpha === 1, `lifted ${liftedOpacity} ${liftedAlpha}`;
	assert restingOpacity === 1 && restingAlpha === 0, `resting ${restingOpacity} ${restingAlpha}`;
}

test "a focused native TextInput in content that an Errored parks loses its focus" {
	const [broken, setBroken] = createSignal(0);
	const handles: TextInputHandle[] = [];
	let log = "";
	const boom: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		createRenderEffect<int32>(
			(p: int32 | null): int32 => broken(),
			(v: int32, p: int32 | null): Cleanup | null => { if (v === 1) { throw new Error("late"); } return null; },
		);
	};
	const app = (): NeonNode => <View>
		<Errored fallback={() => <Text>sorry</Text>}>
			<TextInput ref={(h: TextInputHandle): void => { handles.push(h); }} onBlur={(e: NeonEvent): void => { log += "blur;"; }} />
			{boom}
		</Errored>
	</View>;
	runApp(app);
	const tag = nmLastInputTag();
	handles[0].focus();
	assert nmFocused(tag) === 1, "the input is focused while its content shows";
	setBroken(1);
	flush();
	assert nmFocused(tag) === 0 && log === "blur;", "parking the content took the focus away: " + log;
	assert !handles[0].isFocused(), "and the handle follows";
	nmTeardown();
}

test "the control channel drives the native host: the tree, a press by text through the touch path, a typed value" {
	let log = "";
	const app = (): NeonNode => <View style={{ width: 300, height: 200 }}>
		<Pressable style={{ width: 100, height: 40 }} onPress={(): void => { log += "press;"; }}>go</Pressable>
		<TextInput style={{ width: 200, height: 30 }} value="Ada" onChangeText={(t: string): void => { log += "change " + t + ";"; }} />
	</View>;
	runApp(app);
	nmLoop();
	assert devDriver() !== null, "mounting registers the driver";
	const lines: string[] = [];
	const s = new ControlSession((line: string): void => { lines.push(line); });
	handleRequest(s, `{"jsonrpc":"2.0","id":1,"method":"press","params":{"target":"text:go"}}`);
	nmLoop();
	assert lines[0].includes(`"result":{"x":8.5,"y":10.5}`), "the centre of the text node, inside the pressable: " + lines[0];
	assert log === "press;", "the press reaches onPress once: " + log;
	const input = nmLastInputTag();
	nmControl(input, 1, "");
	nmControl(input, 0, "Ada L");
	nmLoop();
	handleRequest(s, `{"jsonrpc":"2.0","id":2,"method":"tree"}`);
	assert lines[1].includes(`"value":"Ada L","focused":true`), "the tree shows what the native field holds: " + lines[1];
	handleRequest(s, `{"jsonrpc":"2.0","id":3,"method":"type","params":{"text":"x"}}`);
	assert lines[2].includes(`"code":-32000,"message":"type threw: native host: type needs a bridge call`), lines[2];
	nmTeardown();
	nmLoop();
	assert devDriver() === null, "teardown drops the driver";
}

test "native gesture registration marks view pressable and phase zero one two activates only on release" {
	let log = "";
	runApp((): NeonNode => <Pressable onPressIn={(): void => { log += "in;"; }}
		onPress={(e: NeonEvent): void => { log += e.pointerOrigin ? "press;" : "unmarked;"; }} />);
	const tag = nmLastPressableTag();
	assert tag > 0, "onPress registration marks the actual native view pressable";
	nmTouchFull(tag, 0, 10, 10, 7000);
	assert log === "in;", "down does not activate";
	nmTouchFull(tag, 1, 10, 10, 7010);
	nmTouchFull(tag, 2, 10, 10, 7010);
	assert log === "in;press;", "up activates once, phase2 is duplicate: " + log;
	nmTouchFull(tag, 0, 10, 10, 8000);
	nmTouchFull(tag, 3, 10, 10, 8010);
	nmTouchFull(tag, 1, 10, 10, 8010);
	nmTouchFull(tag, 2, 10, 10, 8010);
	assert log === "in;press;in;", "cancel cannot resurrect through phase2: " + log;
	nmTeardown();
	nmTouchFull(tag, 0, 10, 10, 9000);
	nmTouchFull(tag, 1, 10, 10, 9010);
	nmTouchFull(tag, 2, 10, 10, 9010);
	assert log === "in;press;in;", "no route survives teardown";
	assert nmReleaseCalls() === nmViewsCreated(), "views released";
}

test "native long gesture phase two stays suppressed and teardown cancels pending timers" {
	const [log, setLog] = createSignal("");
	runApp((): NeonNode => <Pressable delayLongPress={60}
		onLongPress={(): void => { setLog(log() + "long;"); }}
		onPress={(): void => { setLog(log() + "press;"); }} />);
	const tag = nmLastPressableTag();
	nmTouch(tag, 0);
	await sleepAsync(180);
	nmTouch(tag, 1);
	nmTouch(tag, 2);
	assert log() === "long;", "long press is not followed by phase2 activation: " + log();
	nmTouch(tag, 0);
	nmTeardown();
	await sleepAsync(180);
	nmTouch(tag, 2);
	assert log() === "long;", "teardown removes routes and pending long timer: " + log();
	assert nmReleaseCalls() === nmViewsCreated(), "views released";
}
