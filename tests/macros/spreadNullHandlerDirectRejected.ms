import { NeonEvent } from "../../src/render/event";
import { NeonView, mockHost, mockNode, HostNode } from "../../src/render/host";
import { direct } from "../../src/macros/ui/direct";

interface P { onPress: ((e: NeonEvent) => void) | null; }
function view(p: P): NeonView { return direct(<div {...p}>hi</div>); }
const host = mockHost();
const root = mockNode("root");
view({ onPress: null })(host, root as unknown as HostNode, null);
console.log(root.children.length.toString());
