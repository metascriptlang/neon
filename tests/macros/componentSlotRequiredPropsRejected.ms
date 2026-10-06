import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { createComponent } from "../../src/render/component";

function Slot(props: { content: NeonNode }): NeonNode { return props.content; }
function Required(props: { title: string }): NeonNode { return element(<p>{props.title}</p>); }

export const view: NeonNode = element(<Slot content={Required} />);
