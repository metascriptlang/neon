import { createSignal, Accessor } from "../../src/core/signal";
import { NeonEvent } from "../../src/render/event";
import { tag } from "./words";

export interface CounterProps {
	label: Accessor<string>;
}

export function Counter(props: CounterProps): NeonNode {
	const [count, setCount] = createSignal(0);
	const inc: (e: NeonEvent) => void = () => { setCount(count() + 1); };
	return <div id="counter">
		<h2 id="title" style={{ color: "#205080" }}>Counter v1</h2>
		<p id="out">{props.label() + ": " + count().toString() + " " + tag()}</p>
		<button id="inc" onPress={inc}>+</button>
	</div>;
}
