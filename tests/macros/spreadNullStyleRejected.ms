import { NeonNode } from "../../src/render/node";
import { Style } from "../../src/render/style";
import { element } from "../../src/macros/ui/element";

interface P { style: Style | null; }
function view(p: P): NeonNode { return element(<div {...p}>hi</div>); }
console.log(view({ style: null }).tag);
