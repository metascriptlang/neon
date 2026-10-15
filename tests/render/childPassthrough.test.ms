// {expr} child lowering — the classifier decides static vs reactive, and a static
// child is routed by TYPE (string -> text, NeonNode -> itself) instead of being
// hard-lowered to text(). Matrix: child type (string | NeonNode) x static/dynamic.
// Neon is call-based: an expression is reactive iff it syntactically contains a
// call; a bare read like props.children observes nothing and mounts once.

import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
// mountChild is NOT imported here on purpose: it must arrive through globalImports,
// which is how bare-JSX user code gets it.
import { el } from "../../src/render/node";
import { mockHost, mockNode, mockToString, render, HostNode } from "../../src/render/host";

// --- dynamic string child (regression: call stays reactive) ---
test "a call string child stays reactive" {
	const [n, setN] = createSignal("a");
	const root = mockNode("root");
	render(element(<p>{n()}</p>), mockHost(), root as unknown as HostNode);
	setN("b");
	assert mockToString(root) === "<root><p>b</p></root>", "got " + mockToString(root);
}
