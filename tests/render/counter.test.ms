import { createSignal } from "../../src/core/signal";
import { el, evt, text, dynText } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, renderToHost, fireEvent, mockToString } from "../../src/render/host";

test "counter: onClick increments and reactive text updates" {
	const [count, setCount] = createSignal(0);
	const inc = () => setCount(count() + 1);
	const vnode = element(<div><p>{count() + ""}</p><button onClick={inc}>+</button></div>);

	const root: MockNode = mockNode("root");
	renderToHost(vnode, mockHost(), root as unknown as HostNode);
	const div = root.children[0];

	assert mockToString(div.children[0]) === "<p>0</p>" : "initial count 0";
	const button = div.children[1];
	fireEvent(button, "onClick");
	assert mockToString(div.children[0]) === "<p>1</p>" : "count 1 after click";
	fireEvent(button, "onClick");
	assert mockToString(div.children[0]) === "<p>2</p>" : "count 2 after second click";
}
