import { NeonNode, text } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";

interface P { id: string; children: NeonNode; }
function view(p: P): NeonNode { return element(<div {...p}>hi</div>); }
console.log(view({ id: "x", children: <span>k</span> }).tag);
