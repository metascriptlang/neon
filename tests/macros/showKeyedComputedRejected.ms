import { Show } from "../../src/macros/ui/flow";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";

const [on, setOn] = createSignal<boolean>(true);
const [count, setCount] = createSignal<number>(1);
const view: NeonNode = <div><Show when={count()} keyed={on()}><span>shown</span></Show></div>;
