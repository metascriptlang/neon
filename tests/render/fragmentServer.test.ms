import { NeonNode } from "../../src/render/node";
import { renderToString } from "../../src/render/ssr";
import { element } from "../../src/macros/ui/element";
import { View, Text } from "../../src/components/primitives";
import { Accessor } from "../../src/core/signal";

function Pair(props: { label: Accessor<string> }): NeonNode {
	return element(<><p>r1</p><p>r2</p></>);
}

test "a fragment child flattens into its parent" {
	const v: NeonNode = element(<div><><p>a</p><p>b</p></></div>);
	assert renderToString(v) === "<div><p>a</p><p>b</p></div>", "no wrapper node";
}

test "nested fragments flatten all the way" {
	const v: NeonNode = element(<div><><p>a</p><><p>b</p><p>c</p></></></div>);
	assert renderToString(v) === "<div><p>a</p><p>b</p><p>c</p></div>", "one flat child list";
}

test "a top-level fragment renders every root" {
	const v: NeonNode = element(<><p>a</p><p>b</p></>);
	assert renderToString(v) === "<p>a</p><p>b</p>", "multi-root";
}

test "a fragment flattens inside a component tag too" {
	const v: NeonNode = element(<View><><Text>a</Text><Text>b</Text></></View>);
	assert renderToString(v) === "<div class=\"neon-view\"><span class=\"neon-text\">a</span>" +
		"<span class=\"neon-text\">b</span></div>", "component children list stays flat";
}

test "a component may return a fragment" {
	const v: NeonNode = element(<div><Pair label="x" /></div>);
	assert renderToString(v) === "<div><p>r1</p><p>r2</p></div>", "server render";
}

test "an empty fragment contributes no child" {
	assert renderToString(element(<div><></></div>)) === "<div></div>", "erased at compile time";
}

test "a bare empty fragment at the root mounts nothing" {
	assert renderToString(element(<></>)) === "", "renders nothing";
}

test "a fragment picked by a plain value mounts once" {
	const cond: boolean = true;
	const v: NeonNode = <div>{cond && <><p>a</p><p>b</p></>}</div>;
	assert renderToString(v) === "<div><p>a</p><p>b</p><!----></div>", "static condition: " + renderToString(v);
}

function passThrough(n: NeonNode): NeonNode { return n; }

test "a fragment handed to a function that takes a NeonNode mounts every root" {
	const v: NeonNode = <div>{passThrough(<><p>a</p><p>b</p></>)}</div>;
	assert renderToString(v) === "<div><p>a</p><p>b</p></div>", "through a call: " + renderToString(v);
}
