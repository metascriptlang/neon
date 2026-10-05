import { Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { View } from "../../src/components/primitives";

function Count(props: { value: Accessor<number> | number }): NeonNode { return element(<View />); }

export const count: NeonNode = element(<Count value={1} />);
