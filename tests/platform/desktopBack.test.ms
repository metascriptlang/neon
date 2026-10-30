import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/node";
import { NeonEvent, stopPropagation } from "../../src/render/event";
import { render } from "../../src/render/host";
import { AreaKeyAction, AreaKeyEvent, AreaKeyMod, AreaPointerKind } from "../../src/render/voidAreaHandle";
import { Void, View, Text, TextInput } from "../../src/components/primitives";
import { BackHandler } from "../../src/api/backHandler";
import {
	NavigationContainer,
	NavigationContainerRef,
	ScreenProps,
	createNavigationContainerRef,
	createStackNavigator,
} from "../../src/navigation/index";
import { AreaWindow, WindowArea, windowHost, windowNode, deliverKey, deliverPointer, deliverResize } from "../../src/platform/void/windowHost";
import { FontId, addFont } from "../../../void/src/void2d/font";
import { Dispose } from "../../src/core/types";

interface StackParams {
	Home: null;
	Detail: null;
}

const Stack = createStackNavigator<StackParams>();

function Page(props: ScreenProps<StackParams>): NeonNode {
	return <View style={{ width: 200, height: 100 }}><Text>page</Text></View>;
}

function Field(props: ScreenProps<StackParams>): NeonNode {
	return <TextInput style={{ width: 200, height: 40 }} onKeyDown={(e: NeonEvent): void => { stopPropagation(e); }} />;
}

function loadedFont(): FontId {
	const r = addFont("../void/assets/font.ttf");
	if (!r.ok) { throw new Error("the test font did not load; run from the Neon checkout root beside ../void"); }
	return r.value;
}

function openArea(app: () => NeonNode, areas: WindowArea[]): Dispose {
	const window: AreaWindow = {
		name: "test window",
		font: loadedFont(),
		pixelWidth: (): int32 => 640 as int32,
		pixelHeight: (): int32 => 360 as int32,
		requestFrame: (): void => {},
		dirty: (): void => {},
		setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => {},
		opened: (area: WindowArea): void => { areas.push(area); },
		released: (area: WindowArea): void => {},
	};
	const stop = render(<Void>{app()}</Void>, windowHost(window), windowNode("window"));
	deliverResize(areas[0], 640 as int32, 360 as int32, 1.0);
	areas[0].vh.layout(areas[0].logicalWidth(), areas[0].logicalHeight());
	return stop;
}

function mountDetail(areas: WindowArea[], ref: NavigationContainerRef): Dispose {
	const stop = openArea((): NeonNode => <NavigationContainer ref={ref}>
		<Stack.Navigator initialRouteName="Home" screenOptions={{ headerShown: false }}>
			<Stack.Screen name="Home" component={Page} />
			<Stack.Screen name="Detail" component={Page} />
		</Stack.Navigator>
	</NavigationContainer>, areas);
	ref.navigate("Detail");
	flush();
	if (ref.currentPath() !== "Detail") { throw new Error("the stack did not reach Detail: " + ref.currentPath()); }
	return stop;
}

const NO_MODS = 0 as BitSet<AreaKeyMod>;

function press(area: WindowArea, code: string, mods: BitSet<AreaKeyMod>): void {
	const e: AreaKeyEvent = { action: AreaKeyAction.Press, key: 0 as int32, scancode: 0 as int32, mods, consumedMods: NO_MODS, unshifted: 0 as int32, text: "" };
	deliverKey(area, e, code);
	flush();
}

function mouse(area: WindowArea, button: int32, pressed: boolean): void {
	deliverPointer(area, { kind: AreaPointerKind.Button, pixelX: 20.0, pixelY: 20.0, button, pressed, dx: 0.0, dy: 0.0 });
	flush();
}

function backChord(): { code: string; mods: BitSet<AreaKeyMod> } {
	when (macos) {
		return { code: "BracketLeft", mods: NO_MODS.incl(AreaKeyMod.Super) };
	}
	return { code: "ArrowLeft", mods: NO_MODS.incl(AreaKeyMod.Alt) };
}

test "the mouse back button walks a stack back on release" {
	const areas: WindowArea[] = [];
	const ref = createNavigationContainerRef();
	const stop = mountDetail(areas, ref);
	mouse(areas[0], 4 as int32, true);
	assert ref.currentPath() === "Detail", "press alone goes nowhere";
	mouse(areas[0], 4 as int32, false);
	assert ref.currentPath() === "Home", ref.currentPath();
	stop();
}

test "the platform's history-back chord walks a stack back" {
	const areas: WindowArea[] = [];
	const ref = createNavigationContainerRef();
	const stop = mountDetail(areas, ref);
	const chord = backChord();
	press(areas[0], chord.code, chord.mods);
	assert ref.currentPath() === "Home", ref.currentPath();
	stop();
}

test "Escape, the forward button and the forward chords leave a stack where it is" {
	const areas: WindowArea[] = [];
	const ref = createNavigationContainerRef();
	const stop = mountDetail(areas, ref);
	press(areas[0], "Escape", NO_MODS);
	mouse(areas[0], 5 as int32, true);
	mouse(areas[0], 5 as int32, false);
	press(areas[0], "BracketRight", NO_MODS.incl(AreaKeyMod.Super));
	press(areas[0], "ArrowRight", NO_MODS.incl(AreaKeyMod.Alt));
	press(areas[0], "ArrowLeft", NO_MODS);
	press(areas[0], "ArrowLeft", NO_MODS.incl(AreaKeyMod.Alt).incl(AreaKeyMod.Shift));
	assert ref.currentPath() === "Detail", ref.currentPath();
	stop();
}

test "a BackHandler listener that returns true consumes the mapped input" {
	const areas: WindowArea[] = [];
	const ref = createNavigationContainerRef();
	const stop = mountDetail(areas, ref);
	let heard = 0;
	const sub = BackHandler.addEventListener("hardwareBackPress", (): boolean => { heard += 1; return true; });
	mouse(areas[0], 4 as int32, false);
	const chord = backChord();
	press(areas[0], chord.code, chord.mods);
	assert heard === 2, `heard ${heard}`;
	assert ref.currentPath() === "Detail", ref.currentPath();
	sub.remove();
	mouse(areas[0], 4 as int32, false);
	assert ref.currentPath() === "Home", ref.currentPath();
	stop();
}

test "a keydown handler that stops propagation keeps the chord from going back" {
	const areas: WindowArea[] = [];
	const ref = createNavigationContainerRef();
	const stop = openArea((): NeonNode => <NavigationContainer ref={ref}>
		<Stack.Navigator initialRouteName="Home" screenOptions={{ headerShown: false }}>
			<Stack.Screen name="Home" component={Page} />
			<Stack.Screen name="Detail" component={Field} />
		</Stack.Navigator>
	</NavigationContainer>, areas);
	ref.navigate("Detail");
	flush();
	areas[0].vh.layout(areas[0].logicalWidth(), areas[0].logicalHeight());
	mouse(areas[0], 1 as int32, true);
	mouse(areas[0], 1 as int32, false);
	const chord = backChord();
	press(areas[0], chord.code, chord.mods);
	assert ref.currentPath() === "Detail", ref.currentPath();
	stop();
}
