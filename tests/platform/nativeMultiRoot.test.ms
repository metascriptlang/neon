import { runApp, mountNativeRoot, NativeRootHandle } from "../../src/platform/native/host";
import { View, Pressable, TextInput } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { DevDriver, DevNode, devDriver } from "../../src/devtools/driver";
import { Accessor, createSignal } from "../../src/core/signal";
import { WindowDimensions, useWindowDimensions } from "../../src/render/environment";
import { Dimensions } from "../../src/api/dimensions";
import { niViewCreate } from "../../src/platform/native/bridge.h";
import {
	nmTeardown, nmTapAt, nmTapAtIn, nmTouchFull, nmResize, nmControl, nmLastInputTag, nmLastPressableTag,
	nmViewsCreated, nmReleaseCalls, nmLastViewTag, nmLayoutWidth,
} from "./nativeBridgeMock.h";

class Window {
	log: string = "";
	layouts: int32 = 0;
	size: string = "";
}

function windowApp(name: string, w: Window): () => NeonNode {
	return (): NeonNode => <View style={{ flex: 1 }} onLayout={(e: NeonEvent): void => { w.layouts += 1; w.size = `${e.width}x${e.height}`; }}>
		<Pressable style={{ width: 100, height: 40 }} onPress={(): void => { w.log += name + " press;"; }}>{name}</Pressable>
		<TextInput style={{ width: 100, height: 30 }} value={name} />
	</View>;
}

function focusedValue(n: DevNode): string {
	if (n.focused) { return n.value ?? ""; }
	for (const c of n.children) {
		const got = focusedValue(c);
		if (got !== "") { return got; }
	}
	return "";
}

function mainFocus(): string {
	return focusedValue((devDriver() as DevDriver).tree());
}

test "two native roots lay out, take taps, resize, focus and dispose apart from each other" {
	const a = new Window();
	const b = new Window();
	runApp(windowApp("a", a));
	const pressA = nmLastPressableTag();
	const inputA = nmLastInputTag();
	assert a.size === "400x800", "the main root lays out at the screen: " + a.size;

	const container = niViewCreate();
	const created = nmViewsCreated();
	const released = nmReleaseCalls();
	const panel: NativeRootHandle = mountNativeRoot(container, 200.0, 100.0, windowApp("b", b));
	const panelViews = nmViewsCreated() - created;
	const inputB = nmLastInputTag();
	assert b.size === "200x100", "the second root lays out at its own size: " + b.size;
	assert a.size === "400x800" && a.layouts === 1, "mounting the second root leaves the first alone: " + a.size;

	nmTapAtIn(container, 10.0, 10.0);
	assert b.log === "b press;" && a.log === "", "a tap in the panel reaches only the panel: " + a.log + "|" + b.log;
	nmTapAt(10.0, 10.0);
	assert a.log === "a press;" && b.log === "b press;", "a tap in the main window reaches only the main root: " + a.log + "|" + b.log;

	nmResize(300.0, 600.0);
	assert a.size === "300x600", "the window resize reaches the main root: " + a.size;
	assert b.size === "200x100" && b.layouts === 1, "the window resize leaves the panel's layout alone: " + b.size;
	panel.resize(150.0, 80.0);
	assert b.size === "150x80", "the panel resize reaches the panel: " + b.size;
	assert a.size === "300x600" && a.layouts === 2, "the panel resize leaves the main root's layout alone: " + a.size;

	nmControl(inputA, 1, "a");
	nmControl(inputB, 1, "b");
	assert mainFocus() === "a", "focusing the panel's field keeps the main window's focus: " + mainFocus();
	nmControl(inputB, 2, "b");
	assert mainFocus() === "a", "blurring the panel's field keeps the main window's focus: " + mainFocus();
	nmControl(inputB, 1, "b");

	nmTouchFull(pressA, 0, 10.0, 10.0, 5000000.0);
	panel.dispose();
	assert nmReleaseCalls() - released === panelViews, "dispose releases exactly the panel's views: " + (nmReleaseCalls() - released).toString() + " of " + panelViews.toString();
	assert mainFocus() === "a", "disposing the panel keeps the main window's focus: " + mainFocus();
	nmTouchFull(pressA, 1, 10.0, 10.0, 5000010.0);
	nmTouchFull(pressA, 2, 10.0, 10.0, 5000010.0);
	assert a.log === "a press;a press;", "a press in flight in the main window survives the panel's dispose: " + a.log;
	nmTapAt(10.0, 10.0);
	assert a.log === "a press;a press;a press;" && b.log === "b press;", "the main root keeps taking taps: " + a.log;
	nmResize(400.0, 800.0);
	assert a.size === "400x800", "the main root keeps laying out: " + a.size;
	nmTeardown();
}

class Sizes {
	window: Accessor<WindowDimensions> | null = null;
	dimensionsGet: string = "";
}

function sizeApp(s: Sizes): () => NeonNode {
	return (): NeonNode => {
		s.window = useWindowDimensions();
		const d = Dimensions.get("window");
		s.dimensionsGet = `${d.width}x${d.height}`;
		return <View style={{ flex: 1 }} />;
	};
}

function shown(s: Sizes): string {
	const w = (s.window as Accessor<WindowDimensions>)();
	return `${w.width}x${w.height}`;
}

test "each native root's useWindowDimensions answers its own size, and Dimensions.get answers the main window" {
	const main = new Sizes();
	const side = new Sizes();
	runApp(sizeApp(main));
	const panel: NativeRootHandle = mountNativeRoot(niViewCreate(), 200.0, 100.0, sizeApp(side));
	assert shown(main) === "400x800" && shown(side) === "200x100", "each root reads its own size: " + shown(main) + "|" + shown(side);
	assert side.dimensionsGet === "400x800", "Dimensions.get inside the panel answers the main window: " + side.dimensionsGet;
	panel.resize(150.0, 80.0);
	assert shown(side) === "150x80" && shown(main) === "400x800", "the panel resize reaches only the panel: " + shown(main) + "|" + shown(side);
	nmResize(300.0, 600.0);
	assert shown(main) === "300x600" && shown(side) === "150x80", "the window resize reaches only the main root: " + shown(main) + "|" + shown(side);
	panel.dispose();
	nmResize(400.0, 800.0);
	nmTeardown();
}

test "one input batch lays out many dirty native roots without nesting them" {
	const [width, setWidth] = createSignal<int32>(10);
	const panels: NativeRootHandle[] = [];
	const tags: int32[] = [];
	runApp((): NeonNode => <Pressable
		style={{ width: 100, height: 40 }}
		onPress={(): void => { setWidth(20); }}
	/>);
	for (let i: int32 = 0; i < 32; i += 1) {
		panels.push(mountNativeRoot(
			niViewCreate(), 200.0, 100.0,
			(): NeonNode => <Pressable style={{ width: width(), height: 10 }} />,
		));
		tags.push(nmLastViewTag());
	}
	try {
		nmTapAt(10.0, 10.0);
		assert width() === 20;
		for (const tag of tags) {
			assert nmLayoutWidth(tag) === 20, `root tag ${tag}: ${nmLayoutWidth(tag)}`;
		}
	} finally {
		for (const panel of panels) { panel.dispose(); }
		nmTeardown();
	}
}

test "onLayout can dirty a root already laid out in the same batch" {
	const [firstWidth, setFirstWidth] = createSignal<int32>(10);
	const [secondWidth, setSecondWidth] = createSignal<int32>(10);
	runApp((): NeonNode => <Pressable
		style={{ width: 100, height: 40 }}
		onPress={(): void => { setFirstWidth(20); setSecondWidth(20); }}
	/>);
	const first = mountNativeRoot(
		niViewCreate(), 200.0, 100.0,
		(): NeonNode => <Pressable style={{ width: firstWidth(), height: 10 }} />,
	);
	const tag = nmLastViewTag();
	const second = mountNativeRoot(
		niViewCreate(), 200.0, 100.0,
		(): NeonNode => <View style={{ width: secondWidth(), height: 10 }}
			onLayout={(e: NeonEvent): void => {
				if (e.width > 10) { setFirstWidth((e.width * 2) as int32); }
			}}
		/>,
	);
	try {
		nmTapAt(10.0, 10.0);
		assert nmLayoutWidth(tag) === 40;
	} finally {
		second.dispose();
		first.dispose();
		nmTeardown();
	}
}

test "a layout feedback loop between roots is refused and the drain recovers" {
	const [firstWidth, setFirstWidth] = createSignal<int32>(10);
	const [secondWidth, setSecondWidth] = createSignal<int32>(10);
	let enabled = false;
	runApp((): NeonNode => <Pressable
		style={{ width: 100, height: 40 }}
		onPress={(): void => { enabled = true; setFirstWidth(20); }}
	/>);
	const first = mountNativeRoot(
		niViewCreate(), 200.0, 100.0,
		(): NeonNode => <View style={{ width: firstWidth(), height: 10 }}
			onLayout={(e: NeonEvent): void => {
				if (enabled) { setSecondWidth(e.width as int32); }
			}}
		/>,
	);
	const second = mountNativeRoot(
		niViewCreate(), 200.0, 100.0,
		(): NeonNode => <View style={{ width: secondWidth(), height: 10 }}
			onLayout={(e: NeonEvent): void => {
				if (enabled) { setFirstWidth(e.width === 10 ? 20 : 10); }
			}}
		/>,
	);
	let refused = "";
	try { nmTapAt(10.0, 10.0); }
	catch (e) { refused = e.message; }
	enabled = false;
	try {
		assert refused.includes("still change the layout after 8 passes"), refused;
		first.resize(150.0, 80.0);
		second.resize(150.0, 80.0);
	} finally {
		second.dispose();
		first.dispose();
		nmTeardown();
	}
}
