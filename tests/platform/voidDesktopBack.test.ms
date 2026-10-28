import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/node";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { render } from "../../src/render/host";
import { View, ViewHandle, Text, TextInput, TextInputHandle } from "../../src/components/primitives";
import { createVoidHostWith, VoidHost } from "../../src/platform/void/host";
import { Scene2D } from "../../../void/src/void2d/node";
import { paint as paintScene } from "../../../void/src/void2d/scene";
import { frameEnd } from "../../../void/src/void2d/draw";
import { rgba } from "../../../void/src/void2d/types";
import { FontId, addFont, registerFace, FontStyle as FaceStyle } from "../../../void/src/void2d/font";
import { dispatchHardwareBackPress } from "../../src/api/backHandler";
import { ManualFrames, useManualFrames } from "../../src/animation/index";
import {
	ScreenProps, NavigationContainer, NavigationContainerRef, createNavigationContainerRef, createStackNavigator,
} from "../../src/navigation/index";

const clock: ManualFrames = useManualFrames();
interface P { Home: null; Detail: null; }
const Stack = createStackNavigator<P>();

function loadedFont(): FontId {
	const r = addFont("../void/assets/font.ttf");
	if (!r.ok) { throw new Error("the test font did not load; run from the Neon checkout root beside ../void"); }
	return r.value;
}

function host(): VoidHost {
	registerFace("../void/assets/font.ttf", "../void/assets/font.ttf", 400, FaceStyle.Normal);
	registerFace("../void/assets/font.ttf", "../void/assets/font.ttf", 700, FaceStyle.Normal);
	return createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), loadedFont(), "../void/assets/font.ttf");
}

function settle(vh: VoidHost): void {
	clock.runAll();
	flush();
	vh.layout(400.0, 300.0);
	vh.scene.paintScene(400.0, 300.0, 1.0);
	frameEnd();
	vh.scene.clearChanges();
}

function Home(props: ScreenProps<P>): NeonNode {
	return <View><Text>home</Text></View>;
}

function Detail(props: ScreenProps<P>): NeonNode {
	return <View><Text>detail</Text></View>;
}

function escapeBack(e: NeonEvent): void {
	if (e.code === "Escape") { dispatchHardwareBackPress(); }
}

function keyUp(vh: VoidHost, code: string): void {
	const e = neonEvent("keyup");
	e.key = code;
	e.code = code;
	vh.keyUp(e);
	settle(vh);
}

function mount(vh: VoidHost, ref: NavigationContainerRef, field: boolean, consume: boolean): TextInputHandle | null {
	let shell: ViewHandle | null = null;
	let input: TextInputHandle | null = null;
	render(<View style={{ flex: 1 }} focusable onKeyUp={escapeBack} ref={(h: ViewHandle): void => { shell = h; }}>
		<NavigationContainer ref={ref}>
			<Stack.Navigator initialRouteName="Home">
				<Stack.Screen name="Home" component={Home} />
				<Stack.Screen name="Detail" component={Detail} />
			</Stack.Navigator>
		</NavigationContainer>
		{field ? <TextInput style={{ width: 100, height: 20 }}
			onKeyUp={(e: NeonEvent): void => { if (consume && e.code === "Escape") { e.stopPropagation(); } }}
			ref={(h: TextInputHandle): void => { input = h; }} /> : null}
	</View>, vh.host, vh.root);
	settle(vh);
	(shell as ViewHandle).focus();
	return input;
}

test "escape key-up on the window root goes back from a pushed screen" {
	const vh = host();
	const ref = createNavigationContainerRef();
	mount(vh, ref, false, false);
	ref.navigate("Detail");
	settle(vh);
	assert ref.currentPath() === "Detail", "pushed: " + ref.currentPath();
	keyUp(vh, "Escape");
	assert ref.currentPath() === "Home", "escape went back: " + ref.currentPath();
}

test "escape key-up at the root of the stack does nothing" {
	const vh = host();
	const ref = createNavigationContainerRef();
	mount(vh, ref, false, false);
	keyUp(vh, "Escape");
	assert ref.currentPath() === "Home", "still at the root: " + ref.currentPath();
}

test "a key other than escape does not go back" {
	const vh = host();
	const ref = createNavigationContainerRef();
	mount(vh, ref, false, false);
	ref.navigate("Detail");
	settle(vh);
	keyUp(vh, "Backspace");
	assert ref.currentPath() === "Detail", "backspace is not back: " + ref.currentPath();
}

test "a focused text input that consumes escape keeps the screen, one that does not lets it bubble to back" {
	const vh = host();
	const ref = createNavigationContainerRef();
	const input = mount(vh, ref, true, true);
	ref.navigate("Detail");
	settle(vh);
	(input as TextInputHandle).focus();
	keyUp(vh, "Escape");
	assert ref.currentPath() === "Detail", "the input consumed escape: " + ref.currentPath();

	const vh2 = host();
	const ref2 = createNavigationContainerRef();
	const input2 = mount(vh2, ref2, true, false);
	ref2.navigate("Detail");
	settle(vh2);
	(input2 as TextInputHandle).focus();
	keyUp(vh2, "Escape");
	assert ref2.currentPath() === "Home", "an input that ignores escape lets it reach the root: " + ref2.currentPath();
}
