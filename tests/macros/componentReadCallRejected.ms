import { createSignal, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";

interface CountProps { n: Accessor<int32>; }

function Count(props: CountProps): NeonNode {
	const shown = props.n();
	return element(<p>{shown.toString()}</p>);
}

const [n, setN] = createSignal<int32>(1);
export const view: NeonNode = element(<Count n={n()} />);
