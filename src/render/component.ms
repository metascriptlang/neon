// createComponent — Solid's runtime component helper: the element macro emits
// createComponent(Counter, props) for a capitalized JSX tag. The body is deferred
// to mount and runs untracked (probe/componentSemantics.ms proves the semantics).

import { untrack } from "../core/signal";
import { NeonNode, componentNode } from "./node";

export function createComponent<P>(Comp: (props: P) => NeonNode, props: P): NeonNode {
	return componentNode(() => {
		return untrack(() => Comp(props));
	}, new Map<string, unknown>());
}
