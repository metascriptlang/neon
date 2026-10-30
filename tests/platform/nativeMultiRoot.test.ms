import { runApp, mountNativeRoot, NativeRootHandle } from "../../src/platform/native/host";
import { View, Pressable, TextInput } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { DevDriver, DevNode, devDriver } from "../../src/devtools/driver";
import { Accessor } from "../../src/core/signal";
import { WindowDimensions, useWindowDimensions } from "../../src/render/environment";
import { Dimensions } from "../../src/api/dimensions";
import { niViewCreate } from "../../src/platform/native/bridge.h";
import {
	nmTeardown, nmTapAt, nmTapAtIn, nmTouchFull, nmResize, nmControl, nmLastInputTag, nmLastPressableTag,
	nmViewsCreated, nmReleaseCalls,
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
