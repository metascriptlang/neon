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
import { renderToString } from "../../src/render/ssr";

// --- static string child (regression: must stay text, isDyn false) ---
test "a static string child renders once" {
	const label = "hi";
	const node = element(<p>{label}</p>);
	assert renderToString(node) === "<p>hi</p>", "got " + renderToString(node);
}

// --- dynamic string child (regression: call stays reactive) ---
test "a call string child stays reactive" {
	const [n, setN] = createSignal("a");
	const root = mockNode("root");
	render(element(<p>{n()}</p>), mockHost(), root as unknown as HostNode);
	setN("b");
	assert mockToString(root) === "<root><p>b</p></root>", "got " + mockToString(root);
}

// --- static NeonNode child: THE BUG. props.children is a member read (no call),
//     so it is static and must pass through as a node, not be stringified. ---
interface BoxProps { child: NeonNode; }

function Box(props: BoxProps): NeonNode {
	return element(<div>{props.child}</div>);
}

test "a NeonNode-typed static child passes through" {
	const inner = element(<p>hi</p>);
	const node = Box({ child: inner });
	assert renderToString(node) === "<div><p>hi</p></div>", "got " + renderToString(node);
}

// --- static NeonNode child via a bare const (identifier, not member) ---
test "a NeonNode const child passes through" {
	const inner = element(<span>x</span>);
	const node = element(<div>{inner}</div>);
	assert renderToString(node) === "<div><span>x</span></div>", "got " + renderToString(node);
}
