import { createSignal } from "../../src/core/signal";
import { el, text, dynText } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, renderToHost, mockToString } from "../../src/render/host";

test "renderToHost builds tree and binds reactive text (push)" {
	const [name, setName] = createSignal("world");
	const vnode = element(<p>Hi {name()}</p>);
	const root: MockNode = mockNode("root");
	renderToHost(vnode, mockHost(), root as unknown as HostNode);
	assert mockToString(root.children[0]) === "<p>Hi world</p>", "initial host render";
	setName("neon");
	assert mockToString(root.children[0]) === "<p>Hi neon</p>", "host text updated via effect";
}
