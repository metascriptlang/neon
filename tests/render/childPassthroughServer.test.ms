import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";

// --- static string child (regression: must stay text, isDyn false) ---
test "a static string child renders once" {
	const label = "hi";
	const node = element(<p>{label}</p>);
	assert renderToString(node) === "<p>hi</p>", "got " + renderToString(node);
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
