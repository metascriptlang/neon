import { NeonView } from "../../src/render/host";
import { createSignal } from "../../src/core/signal";
import { createStyles, styleOf } from "../../src/macros/ui/style";

const sheet = createStyles({ box: { width: 200 } });
const [w, setW] = createSignal<number>(1);
const v: NeonView = <div style={[sheet.box, { height: w() }]}>hi</div>;
console.log(v === null);
