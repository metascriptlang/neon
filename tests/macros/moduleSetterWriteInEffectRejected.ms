import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";

const [count, setCount] = createSignal<int32>(0);

function Count(): NeonNode {
	createEffect<int32>(
		(prev: int32 | null): int32 => { setCount(1); return count(); },
		(value: int32, prev: int32 | null): Cleanup | null => null,
	);
	return element(<p>{count().toString()}</p>);
}

export const view: NeonNode = element(<Count />);
