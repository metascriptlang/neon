import { NeonView } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { createSignal } from "../../src/core/signal";
import { createStyles, styleOf } from "../../src/macros/ui/style";

const sheet = createStyles({ box: { width: 200 } });
const [w, setW] = createSignal<number>(1);
const pick = (): Style => { const s: Style = { height: w() }; return s; };
const v: NeonView = <div style={[sheet.box, pick()]}>hi</div>;
console.log(v === null);
