import { el, attr, evt, dynText, NeonNode } from "../../../src/render/node";
import { NeonEvent } from "../../../src/render/event";
import { createSignal } from "../../../src/core/signal";

export function Counter(props: { label: string }): NeonNode {
	const [count, setCount] = createSignal<int32>(0);
	return el("button", [attr("id", "lazyCount")], [evt("click", (e: NeonEvent): void => { setCount(count() + 1); })], dynText((): string => props.label + " " + count().toString()));
}
