// createComponent — Solid's runtime component helper: the element macro emits
// createComponent(Counter, props) for a capitalized JSX tag. The body is deferred
// to mount and runs untracked (probe/componentSemantics.ms proves the semantics).

import { untrack } from "../core/signal";
import { Host, HostNode, NeonNode } from "./hostTypes";

export function createComponent<P>(Comp: (props: P) => NeonNode, props: P): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		untrack((): number => { Comp(props)(host, parent, before); return 0; });
	};
}
