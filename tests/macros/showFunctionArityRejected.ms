import { Show } from "../../src/macros/ui/flow";
import { createSignal, Accessor } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";

const [count, setCount] = createSignal<number>(1);
const view: NeonNode = <div><Show when={count()}>{(c: Accessor<number>, extra: number): NeonNode => <span>{c().toString()}</span>}</Show></div>;
