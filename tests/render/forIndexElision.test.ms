import { NeonNode } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockHost, mockNode, render } from "../../src/render/host";
import { createSignal, Accessor } from "../../src/core/signal";

let seen = "";

function declaredIndex(declared: boolean | null): string {
	return declared === null ? "absent" : ((declared as boolean) ? "true" : "false");
}

function For<T>(props: {
	each: Accessor<T[]>;
	children: (item: T, index: Accessor<number>) => NeonNode;
	fallback?: NeonNode | null;
	usesIndex?: boolean | null;
}): NeonNode {
	seen = declaredIndex(props.usesIndex);
	return element(<i></i>);
}

function ForKeyedBy<T, K>(props: {
	each: Accessor<T[]>;
	keyed: (item: T) => K;
	children: (item: Accessor<T>, index: Accessor<number>) => NeonNode;
	fallback?: NeonNode | null;
	usesIndex?: boolean | null;
}): NeonNode {
	seen = declaredIndex(props.usesIndex);
	return element(<i></i>);
}

interface Row {
	id: number;
}

const [xs, _setXs] = createSignal<string[]>(["a"]);
const [rows, _setRows] = createSignal<Row[]>([{ id: 1 }]);

function namedRow(s: string, i: Accessor<number>): NeonNode {
	return element(<li>{s}</li>);
}

function decided(view: NeonNode): string {
	seen = "unset";
	const dispose = render(view, mockHost(), mockNode("root") as unknown as HostNode);
	dispose();
	return seen;
}

test "map.ts:75 For is told a one-parameter row never reads its index" {
	assert decided(element(<ul><For each={xs()}>{(s: string): NeonNode => element(<li>{s}</li>)}</For></ul>)) === "false", "one parameter";
}

test "map.ts:75 For is told a two-parameter row that never names its index does not read it" {
	assert decided(element(<ul><For each={xs()}>{(s: string, i: Accessor<number>): NeonNode => element(<li>{s}</li>)}</For></ul>)) === "false", "index never named";
}

test "map.ts:75 For is told a row reads its index wherever the row names it" {
	assert decided(element(<ul><For each={xs()}>{(s: string, i: Accessor<number>): NeonNode => element(<li>{s + i().toString()}</li>)}</For></ul>)) === "true", "JSX child";
	assert decided(element(<ul><For each={xs()}>{(s: string, i: Accessor<number>): NeonNode => element(<li title={i().toString()}>{s}</li>)}</For></ul>)) === "true", "JSX attribute";
	assert decided(element(<ul><For each={xs()}>{(s: string, i: Accessor<number>): NeonNode => element(<li>{`${s}#${i()}`}</li>)}</For></ul>)) === "true", "template literal";
	assert decided(element(<ul><For each={xs()}>{(s: string, i: Accessor<number>): NeonNode => element(<li><b>{s}</b><b>{((): string => i().toString())()}</b></li>)}</For></ul>)) === "true", "nested closure under nested elements";
	assert decided(element(<ul><For each={xs()}>{(s: string, i: Accessor<number>): NeonNode => { const at = i; return <li>{s}</li>; }}</For></ul>)) === "true", "a statement body";
}

test "map.ts:75 For is told a row that rebinds the index name reads it" {
	assert decided(element(<ul><For each={xs()}>{(s: string, i: Accessor<number>): NeonNode => element(<li>{((i: number): string => i.toString())(1)}</li>)}</For></ul>)) === "true", "a nested parameter named like the index";
}

test "map.ts:75 For is told a named row function reads its index" {
	assert decided(element(<ul><For each={xs()}>{namedRow}</For></ul>)) === "true", "a row the macro cannot read";
}

test "map.ts:75 a usesIndex written on the tag wins over the macro" {
	assert decided(element(<ul><For each={xs()} usesIndex={false}>{namedRow}</For></ul>)) === "false", "false on a named row";
	assert decided(element(<ul><For each={xs()} usesIndex={true}>{(s: string): NeonNode => element(<li>{s}</li>)}</For></ul>)) === "true", "true on a one-parameter row";
}

test "map.ts:75 a lowered map is told its one-parameter row never reads an index" {
	assert decided(element(<ul>{xs().map((s: string): NeonNode => element(<li>{s}</li>))}</ul>)) === "false", "map row";
}

test "map.ts:97 ForKeyedBy is told whether the row reads its index" {
	const key = (r: Row): number => r.id;
	assert decided(element(<ul><For each={rows()} keyed={key}>{(r: Accessor<Row>): NeonNode => element(<li>{r().id.toString()}</li>)}</For></ul>)) === "false", "one parameter";
	assert decided(element(<ul><For each={rows()} keyed={key}>{(r: Accessor<Row>, i: Accessor<number>): NeonNode => element(<li>{r().id.toString()}</li>)}</For></ul>)) === "false", "index never named";
	assert decided(element(<ul><For each={rows()} keyed={key}>{(r: Accessor<Row>, i: Accessor<number>): NeonNode => element(<li>{r().id.toString() + i().toString()}</li>)}</For></ul>)) === "true", "index read";
}
