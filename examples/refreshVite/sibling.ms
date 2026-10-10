import { createSignal, Accessor } from "../../src/core/signal";
import { NeonEvent } from "../../src/render/event";

export interface TallyProps {
	name: Accessor<string>;
}

export function Tally(props: TallyProps): NeonNode {
	const [count, setCount] = createSignal(0);
	const inc: (e: NeonEvent) => void = () => { setCount(count() + 1); };
	return <div id="tally">
		<span id="tallyOut">{props.name() + ": " + count().toString()}</span>
		<button id="tallyInc" onPress={inc}>+</button>
	</div>;
}
