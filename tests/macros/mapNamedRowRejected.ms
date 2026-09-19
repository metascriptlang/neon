import { NeonNode } from "../../src/render/node";
import { createSignal, Accessor } from "../../src/core/signal";

function row(s: string, i: Accessor<number>): NeonNode {
	return <li>{s + i.toString()}</li>;
}

const [items, setItems] = createSignal<string[]>(["a", "b"]);
const v: NeonNode = <ul>{items.map(row)}</ul>;
console.log(v === null);
