import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { element } from "../../src/macros/ui/element";

interface P { onPress: ((e: NeonEvent) => void) | null; }
function view(p: P): NeonNode { return element(<div {...p}>hi</div>); }
console.log(view({ onPress: null }).tag);
