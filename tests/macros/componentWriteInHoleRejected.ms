import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";

function Count(): NeonNode {
	const [count, setCount] = createSignal<int32>(0);
	return element(<p>{match (count()) { _ => { setCount(1); return "done"; } }}</p>);
}

export const view: NeonNode = element(<Count />);
