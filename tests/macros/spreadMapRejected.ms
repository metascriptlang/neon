import { NeonNode } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";

const m: Map<string, string> = new Map<string, string>();
const v: NeonNode = element(<div {...m}>hi</div>);
console.log(v.tag);
