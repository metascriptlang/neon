import { createSignal, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";

interface CountProps { n: Accessor<int32>; }

function Count(props: CountProps): NeonNode {
	const next: int32 = props.n + 1;
	return element(<p>{next.toString()}</p>);
}

const [n, setN] = createSignal<int32>(1);
export const view: NeonNode = element(<Count n={n()} />);
