import { NeonNode, el } from "../../src/render/node";
import { createSignal } from "../../src/core/signal";

interface CardProps { children: NeonNode; }
function Card(props: CardProps): NeonNode { return <section>{props.children}</section>; }
const [x, setX] = createSignal("v");
const v: NeonNode = <div><Card>
	{x()}
</Card></div>;
console.log(v === null);
