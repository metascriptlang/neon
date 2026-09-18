import { NeonNode } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { createSignal } from "../../src/core/signal";
import { createMemo } from "../../src/core/memo";
import { createStyles, styleOf } from "../../src/macros/ui/style";

const sheet = createStyles({ box: { width: 200 } });
const [w, setW] = createSignal<number>(1);
const acc = createMemo((): Style => { const s: Style = { height: w() }; return s; });
const v: NeonNode = <div style={[sheet.box, acc]}>hi</div>;
console.log(v === null);
