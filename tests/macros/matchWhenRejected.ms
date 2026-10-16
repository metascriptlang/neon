import { Match } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";

const view: NeonNode = <div><Match when={true}><span>shown</span></Match></div>;
