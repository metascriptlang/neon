import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { View } from "../../src/components/primitives";

function Badge(props: { label: string }): NeonNode { return element(<View />); }

export const badge: NeonNode = element(<Badge label="a" lable="b" />);
