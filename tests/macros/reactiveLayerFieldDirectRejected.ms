import { NeonView } from "../../src/render/host";
import { createSignal } from "../../src/core/signal";

const [w, setW] = createSignal<number>(1);
const v: NeonView = <div style={[{ width: w() }, { height: 2 }]}>hi</div>;
console.log(v === null);
