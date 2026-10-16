import { Show, Match, Case } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";

const view: NeonNode = <div><Show when={true}><Case when={true}><span>shown</span></Case></Show></div>;
