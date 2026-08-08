import { createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
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

test "reactive attr: one effect per spot, upsert in place, dispose stops tracking" {
	const [cls, setCls] = createSignal("red");
	const root: MockNode = mockNode("root");
	createRoot((dispose) => {
		renderToHost(element(<p class={cls()}>x</p>), mockHost(), root as unknown as HostNode);
		assert mockToString(root.children[0]) === "<p class=\"red\">x</p>", "initial mount";
		setCls("blue");
		assert mockToString(root.children[0]) === "<p class=\"blue\">x</p>", "attr updated via effect";
		assert root.children[0].attrs.length === 1, "upsert — no duplicate attr entries";
		dispose();
		setCls("green");
		assert mockToString(root.children[0]) === "<p class=\"blue\">x</p>", "no update after dispose";
		return 0;
	});
}
