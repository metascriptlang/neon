import { flush } from "../../src/core/runtime";
import { createSignal, accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { Style } from "../../src/render/style";
import { Host, HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Text, TextInput, View } from "../../src/components/primitives";
import { InputAccessoryView, inputAccessoryViewNode } from "../../src/components/inputAccessoryView";

function overlayOf(host: Host): MockNode {
	return (host.overlayRoot as (n: HostNode) => HostNode)(mockNode("any") as unknown as HostNode) as unknown as MockNode;
}

test "InputAccessoryView renders nothing off iOS, as RN does on Android" {
	const host = mockHost();
	const root: MockNode = mockNode("root");
	render(element(<View><InputAccessoryView nativeID="bar"><Text>tools</Text></InputAccessoryView></View>), host, root as unknown as HostNode);
	assert mockToString(root) === "<root><view></view></root>", "the app tree: " + mockToString(root);
	assert mockToString(overlayOf(host)) === "<overlay></overlay>", "the overlay: " + mockToString(overlayOf(host));
}

test "the accessory mounts its children into the overlay root with its nativeID and backgroundColor" {
	const [color, setColor] = createSignal("#eeeeee");
	const host = mockHost();
	const root: MockNode = mockNode("root");
	const bar = inputAccessoryViewNode({ nativeID: accessor((): string => "bar"), backgroundColor: accessor((): string => color()), children: element(<Text>tools</Text>) });
	render(element(<View><TextInput inputAccessoryViewID="bar" />{bar}</View>), host, root as unknown as HostNode);
	assert mockToString(root).indexOf("tools") < 0, "nothing lands in the app tree: " + mockToString(root);
	assert mockToString(overlayOf(host)) === "<overlay><inputaccessoryview nativeID=\"bar\" backgroundColor=\"#eeeeee\"><text>tools</text></inputaccessoryview></overlay>", "overlay: " + mockToString(overlayOf(host));
	setColor("#222222");
	flush();
	assert mockToString(overlayOf(host)).indexOf("backgroundColor=\"#222222\"") >= 0, "reactive: " + mockToString(overlayOf(host));
	const box = overlayOf(host).children[0].style as Style;
	assert box.position === "absolute" && box.top === 0 && box.left === 0 && box.right === 0, "spans the width from the top";
}

test "the TextInput names its accessory with inputAccessoryViewID" {
	const root: MockNode = mockNode("root");
	render(element(<TextInput inputAccessoryViewID="bar" />), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><textinput inputAccessoryViewID=\"bar\"></textinput></root>", mockToString(root);
}

test "an accessory without nativeID or children" {
	const host = mockHost();
	const root: MockNode = mockNode("root");
	render(element(<View>{inputAccessoryViewNode({ children: element(<Text>sticky</Text>) })}{inputAccessoryViewNode({ nativeID: accessor((): string => "empty") })}</View>), host, root as unknown as HostNode);
	assert mockToString(overlayOf(host)) === "<overlay><inputaccessoryview><text>sticky</text></inputaccessoryview></overlay>", "no attribute without nativeID, nothing without children: " + mockToString(overlayOf(host));
}
