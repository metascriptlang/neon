import { createSignal } from "../../src/core/signal";
import { createMemo } from "../../src/core/memo";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";

function Count(): NeonNode {
	const [count, setCount] = createSignal<int32>(0);
	const doubled = createMemo<int32>((): int32 => { setCount(1); return count() * 2; });
	return element(<p>{doubled().toString()}</p>);
}

export const view: NeonNode = element(<Count />);
