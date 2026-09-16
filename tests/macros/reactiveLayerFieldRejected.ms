import { NeonNode } from "../../src/render/node";
import { createSignal } from "../../src/core/signal";

const [w, setW] = createSignal<number>(1);
const v: NeonNode = <div style={[{ width: w() }, { height: 2 }]}>hi</div>;
console.log(v === null);
