import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { Accessor } from "../../src/core/signal";

interface BadgeProps {
	label: Accessor<string>;
	suffix: Accessor<string>;
}

function Badge(props: BadgeProps): NeonNode { return element(<p>{props.label() + props.suffix()}</p>); }

export const view: NeonNode = element(<Badge label="a" />);
