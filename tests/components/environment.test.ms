import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { HostNode, MockNode, mockNode, mockHost, render, fireEventWith, mockToString } from "../../src/render/host";
import { publishKeyboard, publishSafeArea, useSafeAreaInsets } from "../../src/render/environment";
import { Text, TextInput } from "../../src/components/primitives";
import { SafeAreaView } from "../../src/components/safeAreaView";
import { KeyboardAvoidingView } from "../../src/components/keyboardAvoidingView";
import { StatusBar } from "../../src/components/statusBar";
import { Show } from "../../src/macros/ui/flow";

function styleOf(n: MockNode): Style {
	return n.style as Style;
}

function attrOf(n: MockNode, name: string): string {
	for (const a of n.attrs) {
		if (a.name === name) { return a.value ?? ""; }
	}
	return "<unset>";
}

function laidOut(height: number): NeonEvent {
	const e = neonEvent("layout");
	e.height = height;
	return e;
}

test "SafeAreaView adds the published insets to its own padding" {
	const root: MockNode = mockNode("root");
	render(element(<SafeAreaView style={{ padding: 4, paddingTop: 10, flex: 1 }}><Text>safe</Text></SafeAreaView>), mockHost(), root as unknown as HostNode);
	const box = (): Style => styleOf(root.children[0]);
	assert box().paddingTop === 10 && box().paddingBottom === 4 && box().flex === 1, "no insets yet";
	publishSafeArea(47, 0, 34, 0);
	assert box().paddingTop === 57 && box().paddingBottom === 38 && box().paddingLeft === 4, "insets added";
	const insets = useSafeAreaInsets();
	assert insets().top === 47 && insets().bottom === 34, "the hook reads the same insets";
	publishSafeArea(0, 0, 0, 0);
}

test "KeyboardAvoidingView padding pads by the keyboard height less the vertical offset" {
	const root: MockNode = mockNode("root");
	render(element(<KeyboardAvoidingView behavior="padding" keyboardVerticalOffset={20} style={{ flex: 1 }}>
		<TextInput placeholder="Message" />
	</KeyboardAvoidingView>), mockHost(), root as unknown as HostNode);
	const box = (): Style => styleOf(root.children[0]);
	assert box().paddingBottom === 0, "no keyboard";
	publishKeyboard(300);
	assert box().paddingBottom === 280 && box().flex === 1, "keyboard up";
	publishKeyboard(0);
	assert box().paddingBottom === 0, "keyboard down";
}

test "KeyboardAvoidingView height shrinks from its first frame while the keyboard shows" {
	const [on, setOn] = createSignal(true);
	const root: MockNode = mockNode("root");
	render(element(<KeyboardAvoidingView behavior="height" enabled={on()} style={{ flex: 1 }}><Text>body</Text></KeyboardAvoidingView>), mockHost(), root as unknown as HostNode);
	const view = root.children[0];
	fireEventWith(view, "onLayout", laidOut(700));
	publishKeyboard(300);
	assert styleOf(view).height === 400 && styleOf(view).flex === 0, "shrunk";
	setOn(false);
	assert styleOf(view).height === null && styleOf(view).flex === 1, "disabled restores the style";
	publishKeyboard(0);
}

test "KeyboardAvoidingView position lifts a content view by the keyboard height" {
	const root: MockNode = mockNode("root");
	render(element(<KeyboardAvoidingView behavior="position" contentContainerStyle={{ padding: 8 }}><Text>lifted</Text></KeyboardAvoidingView>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><view><view><text>lifted</text></view></view></root>", "shape: " + mockToString(root);
	const content = root.children[0].children[0];
	publishKeyboard(250);
	assert styleOf(content).bottom === 250 && styleOf(content).position === "relative" && styleOf(content).padding === 8, "lifted";
	publishKeyboard(0);
	assert styleOf(content).bottom === 0, "back down";
}

test "StatusBar applies per prop the most recently mounted value, and restores the rest on unmount" {
	const [dialog, setDialog] = createSignal(false);
	const [hidden, setHidden] = createSignal(false);
	const root: MockNode = mockNode("root");
	render(element(<view>
		<StatusBar barStyle="light-content" backgroundColor="#123456" hidden={hidden()} />
		<Show when={dialog()}><StatusBar barStyle="dark-content" /></Show>
	</view>), mockHost(), root as unknown as HostNode);
	const first = root.children[0].children[0];
	assert styleOf(first).display === "none", "takes no space";
	assert attrOf(first, "statusBarStyle") === "light-content" && attrOf(first, "statusBarBackgroundColor") === "#123456" && attrOf(first, "statusBarHidden") === "false", "first applied";
	setHidden(true);
	assert attrOf(first, "statusBarHidden") === "true", "a prop change re-applies";
	setDialog(true);
	const second = root.children[0].children[1];
	assert attrOf(second, "statusBarStyle") === "dark-content", "the newer one wins its prop";
	assert attrOf(second, "statusBarBackgroundColor") === "#123456" && attrOf(second, "statusBarHidden") === "true", "the older one fills the rest";
	setDialog(false);
	setHidden(false);
	assert attrOf(first, "statusBarStyle") === "light-content" && attrOf(first, "statusBarHidden") === "false", "the first applies again";
}
