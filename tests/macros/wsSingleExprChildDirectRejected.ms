import { NeonNode, el } from "../../src/render/node";
import { NeonView } from "../../src/render/host";
import { createSignal } from "../../src/core/signal";

interface CardProps { children: NeonNode; }
function Card(props: CardProps): NeonNode { return <section>{props.children}</section>; }
const [x, setX] = createSignal("v");
const v: NeonView = <div><Card>
	{x()}
</Card></div>;
console.log(v === null);
