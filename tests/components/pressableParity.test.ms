import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonEvent } from "../../src/render/event";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Pressable, Text, View } from "../../src/components/primitives";

function attrOf(n: MockNode, name: string): string {
	for (const a of n.attrs) {
		if (a.name === name) { return a.value ?? ""; }
	}
	return "<unset>";
}

test "Pressable sends a number hitSlop as four insets and android_ripple as one config" {
	const root: MockNode = mockNode("root");
	const [slop, setSlop] = createSignal(10);
	render(element(<View>
		<Pressable hitSlop={slop()} android_ripple={{ color: "#33ff0000", borderless: true, radius: 24 }} onPress={(e: NeonEvent): void => {}}>
			<Text>tap</Text>
		</Pressable>
	</View>), mockHost(), root as unknown as HostNode);
	const button = root.children[0].children[0];
	const all = attrOf(button, "hitSlop");
	setSlop(6);
	assert all === "10,10,10,10", "a number reaches every edge: " + all;
	assert attrOf(button, "hitSlop") === "6,6,6,6", "follows its signal: " + attrOf(button, "hitSlop");
	assert attrOf(button, "androidRipple") === "#33ff0000,true,24", "ripple: " + attrOf(button, "androidRipple");
}

test "a Pressable without hitSlop or ripple writes neither" {
	const root: MockNode = mockNode("root");
	render(element(<Pressable onPress={(e: NeonEvent): void => {}}><Text>tap</Text></Pressable>), mockHost(), root as unknown as HostNode);
	assert attrOf(root.children[0], "hitSlop") === "<unset>" && attrOf(root.children[0], "androidRipple") === "<unset>", "none";
}
