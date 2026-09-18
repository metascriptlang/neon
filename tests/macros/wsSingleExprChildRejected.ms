import { NeonNode, el } from "../../src/render/node";
import { createSignal } from "../../src/core/signal";

interface CardProps { children: NeonNode; }
function Card(props: CardProps): NeonNode { return <section>{props.children}</section>; }
const [x, setX] = createSignal("v");
const v: NeonNode = <Card>
	{x()}
</Card>;
console.log(v === null);
