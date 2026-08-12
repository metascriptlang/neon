// The converter surface — bare JSX, zero element()/direct() calls, lowered by the
// prelude converter at every settled expected-type boundary. Pins PORT-STATUS #2:
// an app is writable without naming a macro. On js the NeonNode boundary needs its
// own converter (NeonView is a mount closure there); on native the NeonView one
// already covers it via the alias.

import { createSignal } from "../../src/core/signal";
import { NeonNode, renderToString } from "../../src/render/node";
import { renderToHost, mockHost, mockNode, mockToString, HostNode } from "../../src/render/host";

interface CounterProps {
	count: () => number;
	label: string;
}

let counterRuns = 0;

function Counter(props: CounterProps): NeonNode {
	counterRuns = counterRuns + 1;
	return <p class={props.label}>n={props.count().toString()}</p>;
}

test "bare JSX lowers at an annotated const boundary" {
	const v: NeonNode = <div class="box">hi</div>;
	assert renderToString(v) === "<div class=\"box\">hi</div>", renderToString(v);
}

test "bare JSX lowers at a parameter boundary" {
	const host = mockHost();
	const root = mockNode("root");
	renderToHost(<ul><li>a</li></ul>, host, root as unknown as HostNode);
	assert mockToString(root) === "<root><ul><li>a</li></ul></root>", mockToString(root);
}

test "render() mounts bare JSX at the app entry" {
	const [n, setN] = createSignal(1);
	const host = mockHost();
	const root = mockNode("root");
	render(<section><Counter count={n()} label="e" /></section>, host, root as unknown as HostNode);
	assert mockToString(root) === "<root><section><p class=\"e\">n=1</p></section></root>", "initial: " + mockToString(root);
	setN(3);
	assert mockToString(root) === "<root><section><p class=\"e\">n=3</p></section></root>", "after set: " + mockToString(root);
}

test "a component returns bare JSX and stays reactive" {
	counterRuns = 0;
	const [n, setN] = createSignal(1);
	const host = mockHost();
	const root = mockNode("root");
	renderToHost(<div><Counter count={n()} label="c" /></div>, host, root as unknown as HostNode);
	assert mockToString(root) === "<root><div><p class=\"c\">n=1</p></div></root>", "initial: " + mockToString(root);
	setN(5);
	assert mockToString(root) === "<root><div><p class=\"c\">n=5</p></div></root>", "after set: " + mockToString(root);
	assert counterRuns === 1, "signal change must not re-run the body";
}
