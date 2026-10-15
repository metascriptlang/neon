import { For } from "../../src/macros/ui/flow";
import { createSignal, Accessor } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";

const [on, setOn] = createSignal<boolean>(true);
const [xs, setXs] = createSignal<number[]>([1, 2]);
const view: NeonNode = <ul><For each={xs()} keyed={on()}>{(x: number, i: Accessor<number>): NeonNode => <li>{x.toString()}</li>}</For></ul>;
