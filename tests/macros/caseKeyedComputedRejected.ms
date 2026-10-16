import { Match, Case } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";

const wide = true;
const view: NeonNode = <div><Match><Case when={wide} keyed={wide}><span>shown</span></Case></Match></div>;
