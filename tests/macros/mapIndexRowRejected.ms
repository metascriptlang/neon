import { NeonNode } from "../../src/render/node";
import { createSignal } from "../../src/core/signal";

const [items, setItems] = createSignal<string[]>(["a", "b"]);
const v: NeonNode = <ul>{items.map((s: string, i: number): NeonNode => <li>{s + i.toString()}</li>)}</ul>;
console.log(v === null);
