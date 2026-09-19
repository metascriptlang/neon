import { NeonNode } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { createSignal, Accessor } from "../../src/core/signal";

function main(): void {
	const [items, _s] = createSignal<string[]>(["a"]);
	const v: NeonNode = element(<ul>{items.map((s: string, i: Accessor<number>): NeonNode => element(<li>{s + i.toString()}</li>))}</ul>);
	console.log(v === null);
}
main();
