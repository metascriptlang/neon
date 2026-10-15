import { NeonNode } from "../../src/render/node";
import { render, mockHost, mockNode, mockToString, HostNode } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { createSignal, Accessor } from "../../src/core/signal";

function orNone(maybe: NeonNode | null): NeonNode {
	return <div>{maybe ?? <i>none</i>}</div>;
}

test "bare JSX lowers ?? over a nullable node" {
	const a = mockNode("root");
	render(orNone(null), mockHost(), a as unknown as HostNode);
	assert mockToString(a) === "<root><div><i>none</i></div></root>", "null: " + mockToString(a);
	const b = mockNode("root");
	render(orNone(<b>x</b>), mockHost(), b as unknown as HostNode);
	assert mockToString(b) === "<root><div><b>x</b></div></root>", "present: " + mockToString(b);
}

function mountedText(view: NeonNode): string {
	const root = mockNode("root");
	render(view, mockHost(), root as unknown as HostNode);
	return mockToString(root);
}

test "a lowered && needs no flow import" {
	const [on, _s] = createSignal(true);
	const v: NeonNode = element(<div>{on() && <b>yes</b>}</div>);
	assert mountedText(v) === "<root><div><b>yes</b></div></root>", "Show came from the prelude: " + mountedText(v);
}

test "a lowered ternary needs no flow import" {
	const [on, _s] = createSignal(false);
	const v: NeonNode = element(<div>{on() ? <b>y</b> : <i>n</i>}</div>);
	assert mountedText(v) === "<root><div><i>n</i></div></root>", "both arms came from the prelude: " + mountedText(v);
}

test "a lowered map needs no flow import" {
	const [xs, _s] = createSignal<number[]>([1, 2]);
	const v: NeonNode = element(<ul>{xs.map((n: number): NeonNode => element(<li>{n.toString()}</li>))}</ul>);
	assert mountedText(v) === "<root><ul><li>1</li><li>2</li></ul></root>", "For came from the prelude: " + mountedText(v);
}

test "the flow tags are in scope without an import" {
	const [on, _o] = createSignal(true);
	const [xs, _x] = createSignal<number[]>([1]);
	const shown: NeonNode = element(<div><Show when={on()}><b>y</b></Show></div>);
	assert mountedText(shown) === "<root><div><b>y</b></div></root>", "Show tag: " + mountedText(shown);
	const each: NeonNode = element(<ul><For each={xs()}>{(n: number, i: Accessor<number>): NeonNode => element(<li>{n.toString()}</li>)}</For></ul>);
	assert mountedText(each) === "<root><ul><li>1</li></ul></root>", "For tag: " + mountedText(each);
}
