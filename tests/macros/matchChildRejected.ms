import { Match, Case } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";

const view: NeonNode = <div><Match><Case when={false}><i>no</i></Case><span>stray</span></Match></div>;
