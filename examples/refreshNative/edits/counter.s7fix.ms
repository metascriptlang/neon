import { createSignal, Accessor } from "../../src/core/signal";
import { NeonEvent } from "../../src/render/event";
import { word } from "./words";

export interface CounterProps {
	label: Accessor<string>;
}

export function Counter(props: CounterProps): NeonNode {
	const [count, setCount] = createSignal(0);
	const inc: (e: NeonEvent) => void = () => { setCount(count() + 2); };
	return <div>
		<h2>Counter v6</h2>
		<p>{props.label() + ":" + count().toString() + " " + word()}</p>
		<button id="inc" onPress={inc}>+</button>
	</div>;
}

export interface TallyProps {
	name: Accessor<string>;
}

export function Tally(props: TallyProps): NeonNode {
	const [n, setN] = createSignal(0);
	const bump: (e: NeonEvent) => void = () => { setN(n() + 1); };
	return <div>
		<p>{props.name() + "=" + n().toString()}</p>
		<button id="tally" onPress={bump}>t</button>
	</div>;
}
