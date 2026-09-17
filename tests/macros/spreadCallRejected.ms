import { NeonNode } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";

interface P { id: string; }
function makeProps(): P { return { id: "x" }; }
const v: NeonNode = element(<div {...makeProps()}>hi</div>);
console.log(v.tag);
