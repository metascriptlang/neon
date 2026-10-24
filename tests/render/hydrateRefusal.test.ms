import { NeonNode } from "../../src/render/node";
import { createSignal } from "../../src/core/signal";
import { render, hydrate, mockHost, mockNode, mockToString, MockNode, HostNode } from "../../src/render/host";
import { View, Text } from "../../src/components/primitives";
import { Show } from "../../src/macros/ui/flow";
import { flush } from "../../src/core/runtime";

function served(tree: NeonNode): MockNode {
	const root = mockNode("root");
	const dispose = render(tree, mockHost(), root as unknown as HostNode, "");
	dispose();
	return root;
}

test "a hydrate refusal inside a reactive region, caught by the caller, leaves the rebuilt page updating" {
	const [shown, setShown] = createSignal("one");
	const page = (): NeonNode => <View><Show when={true}><h1>x</h1></Show><Text>{shown()}</Text></View>;
	const root = served(<View><p>x</p><Text>one</Text></View>);
	let said = "";
	try {
		hydrate(page(), mockHost(), root as unknown as HostNode);
	} catch (e) { said = e.toString(); }
	assert said.indexOf("<h1>") >= 0, said;
	root.children = [];
	render(page(), mockHost(), root as unknown as HostNode);
	setShown("two");
	flush();
	assert mockToString(root).indexOf("two") >= 0, mockToString(root);
}
