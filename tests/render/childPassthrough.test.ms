// {expr} child lowering — the classifier decides static vs reactive, and a static
// child is routed by TYPE (string -> text, NeonNode -> itself) instead of being
// hard-lowered to text(). Matrix: child type (string | NeonNode) x static/dynamic.
// Neon is call-based: an expression is reactive iff it syntactically contains a
// call; a bare read like props.children observes nothing and mounts once.

import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
// mountChild is NOT imported here on purpose: it must arrive through globalImports,
// which is how bare-JSX user code gets it.
import { el, NeonNode } from "../../src/render/node";
import { mockHost, mockNode, mockToString, render, HostNode } from "../../src/render/host";
import { flush } from "../../src/core/runtime";

// --- dynamic string child (regression: call stays reactive) ---
test "a call string child stays reactive" {
	const [n, setN] = createSignal("a");
	const root = mockNode("root");
	render(element(<p>{n()}</p>), mockHost(), root as unknown as HostNode);
	setN("b");
	flush();
	assert mockToString(root) === "<root><p>b</p></root>", "got " + mockToString(root);
}

test "a static string child renders once" {
	const label = "hi";
	const root = mockNode("root");
	render(element(<p>{label}</p>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><p>hi</p></root>", "got " + mockToString(root);
}

interface BoxProps { child: NeonNode; }

function Box(props: BoxProps): NeonNode {
	return element(<div>{props.child}</div>);
}

test "a NeonNode-typed static child passes through" {
	const inner = element(<p>hi</p>);
	const root = mockNode("root");
	render(Box({ child: inner }), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div><p>hi</p></div></root>", "got " + mockToString(root);
}

test "a NeonNode const child passes through" {
	const inner = element(<span>x</span>);
	const root = mockNode("root");
	render(element(<div>{inner}</div>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><div><span>x</span></div></root>", "got " + mockToString(root);
}
