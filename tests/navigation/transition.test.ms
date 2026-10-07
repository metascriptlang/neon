import { NeonNode } from "../../src/render/node";
import { neonEvent } from "../../src/render/event";
import { ManualFrames } from "../../src/animation/index";
import { Style } from "../../src/render/style";
import { HostNode, MockNode, mockNode, mockHost, render, fireEventWith, fireTouch } from "../../src/render/host";
import { View, Text } from "../../src/components/primitives";
import {
	NavigationContainer,
	NavigationContainerRef,
	ScreenProps,
	createNavigationContainerRef,
	createStackNavigator,
	STACK_DURATION,
} from "../../src/navigation/index";
import { clock, settle } from "./navHarness";

const Stack = createStackNavigator<string>();

function Named(props: ScreenProps<string>): NeonNode {
	return <View><Text>{"screen " + props.route.name}</Text></View>;
}

function mount(ref: NavigationContainerRef): MockNode {
	const root: MockNode = mockNode("root");
	render(<NavigationContainer ref={ref}>
		<Stack.Navigator screenOptions={{ gestureEnabled: true }}>
			<Stack.Screen name="Home" component={Named} />
			<Stack.Screen name="Detail" component={Named} />
			<Stack.Screen name="Sheet" component={Named} options={{ presentation: "modal" }} />
			<Stack.Screen name="Overlay" component={Named} options={{ presentation: "transparentModal" }} />
			<Stack.Screen name="Still" component={Named} options={{ animation: "none" }} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	const stack = root.children[0];
	const e = neonEvent("layout");
	e.width = 400;
	e.height = 800;
	fireEventWith(stack, "onLayout", e);
	return root;
}

function frames(root: MockNode): MockNode[] {
	const out: MockNode[] = [];
	for (const child of root.children[0].children) {
		if (child.tag === "view") { out.push(child); }
	}
	return out;
}

function styleOf(frame: MockNode): Style {
	return frame.style as Style;
}

function shown(frame: MockNode): boolean {
	return styleOf(frame).display !== "none";
}

function transformOf(frame: MockNode): string {
	return styleOf(frame).transform ?? "none";
}

function translation(frame: MockNode): number {
	const text = transformOf(frame);
	const open = text.indexOf("(");
	if (open < 0) { return 0; }
	return parseFloat(text.substring(open + 1, text.indexOf("px")));
}

function steps(ms: number): int32 {
	return Math.ceil(ms / 16) as int32;
}

test "a push slides the new screen in from the right over the one below, which then hides" {
	settle();
	const ref = createNavigationContainerRef();
	const root = mount(ref);
	settle();
	ref.navigate("Detail");
	let list = frames(root);
	assert list.length === 2;
	assert transformOf(list[1]) === "translateX(400px)", transformOf(list[1]);
	clock.step(steps(STACK_DURATION / 2));
	const middle = translation(list[1]);
	assert middle > 0 && middle < 400, "mid-flight " + middle.toString();
	assert shown(list[0]) && shown(list[1]), "both screens show while it moves";
	settle();
	assert transformOf(list[1]) === "none" && !shown(list[0]), "settled";
}

test "a pop slides the screen out to the right and unmounts it when it is gone" {
	const ref = createNavigationContainerRef();
	const root = mount(ref);
	ref.navigate("Detail");
	settle();
	ref.goBack();
	let list = frames(root);
	assert list.length === 2, "the leaving screen stays mounted while it moves";
	assert shown(list[0]) && shown(list[1]);
	clock.step(steps(STACK_DURATION / 2));
	const middle = translation(list[1]);
	assert middle > 0 && middle < 400, "mid-flight " + middle.toString();
	settle();
	list = frames(root);
	assert list.length === 1 && shown(list[0]), "only Home is left";
}

test "a modal slides up, a transparent modal fades, animation none switches at once" {
	const ref = createNavigationContainerRef();
	const root = mount(ref);
	ref.navigate("Sheet");
	assert transformOf(frames(root)[1]) === "translateY(800px)", transformOf(frames(root)[1]);
	settle();
	ref.goBack();
	settle();
	ref.navigate("Overlay");
	assert styleOf(frames(root)[1]).opacity === 0, "fades from 0";
	clock.step(steps(STACK_DURATION / 2));
	const opacity = styleOf(frames(root)[1]).opacity as number;
	assert opacity > 0 && opacity < 1, "mid-fade " + opacity.toString();
	settle();
	ref.goBack();
	settle();
	ref.navigate("Still");
	const list = frames(root);
	assert transformOf(list[1]) === "none" && !shown(list[0]), "no animation";
}

function edgeOf(frame: MockNode): MockNode {
	for (const child of frame.children) {
		const style = child.style;
		if (style !== null && (style as Style).width === 24) { return child; }
	}
	throw new Error("no edge strip");
}

function drag(target: MockNode, xs: number[]): void {
	let t = 5000.0;
	fireTouch(target, "onTouchStart", xs[0], 300, t);
	for (let i = 1; i < xs.length; i += 1) {
		t += 100;
		fireTouch(target, "onTouchMove", xs[i], 300, t);
	}
	t += 100;
	fireTouch(target, "onTouchEnd", xs[xs.length - 1], 300, t);
}

test "a swipe from the left edge drags the screen and pops it past a third of the width" {
	const ref = createNavigationContainerRef();
	const root = mount(ref);
	ref.navigate("Detail");
	settle();
	const detail = frames(root)[1];
	drag(edgeOf(detail), [5, 30, 60, 90]);
	settle();
	assert ref.currentPath() === "Detail", "a short drag springs back";
	assert transformOf(detail) === "none" && !shown(frames(root)[0]);
	const edge = edgeOf(detail);
	fireTouch(edge, "onTouchStart", 5, 300, 9000);
	fireTouch(edge, "onTouchMove", 60, 300, 9100);
	fireTouch(edge, "onTouchMove", 120, 300, 9200);
	const dragged = translation(detail);
	assert dragged > 50 && dragged < 70, "follows the finger from where the drag was granted: " + dragged.toString();
	assert shown(frames(root)[0]), "the screen below shows during the drag";
	fireTouch(edge, "onTouchMove", 250, 300, 9300);
	fireTouch(edge, "onTouchEnd", 250, 300, 9400);
	assert ref.currentPath() === "Home", ref.currentPath();
	settle();
	assert frames(root).length === 1;
}
