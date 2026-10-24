// createComponent — Solid's runtime component helper: the element macro emits
// createComponent(Counter, props) for a capitalized JSX tag. The body is deferred
// to mount and runs untracked (probe/componentSemantics.ms proves the semantics).

import { untrack, createSignal } from "../core/signal";
import { createRenderEffect } from "../core/effect";
import { Cleanup } from "../core/types";
import { createAsyncMemo } from "../core/memo";
import { Host, HostNode, NeonNode } from "./hostTypes";
import { Show } from "../macros/ui/flow";

export function createComponent<P>(Comp: (props: P) => NeonNode, props: P): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const mount = untrack((): NeonNode => Comp(props), "a component body");
		untrack((): number => { mount(host, parent, before); return 0; });
	};
}

// Parked on ~/metascript/.inbox/compiler/2026-09-24-default-import-does-not-parse.md, 2026-10-16-promise-or-null-is-never-null-on-c-and-js.md and 2026-10-24-design-a-property-assigned-onto-a-function-value.md: Solid's `lazy(() => import("./Page"))` reading the default export, one `Promise | null` slot for the load, and `.preload()` on the component.
export function lazy<P>(load: () => Promise<(props: P) => NeonNode>): (props: P) => NeonNode {
	const loading: Promise<boolean>[] = [];
	const loaded: ((props: P) => NeonNode)[] = [];
	const start = (): Promise<boolean> => {
		if (loading.length === 0) {
			const current = load().then((comp): boolean => { loaded.push(comp); return true; });
			loading.push(current);
			current.catch((e): boolean => { if (loading.length > 0 && loading[0] === current) { loading.pop(); } return false; });
		}
		return loading[0];
	};
	return (props: P): NeonNode => (host: Host, parent: HostNode, before: HostNode | null): void => {
		const mount: NeonNode = (h: Host, p: HostNode, b: HostNode | null): void => { createComponent(loaded[0], props)(h, p, b); };
		if (loaded.length > 0) { mount(host, parent, before); return; }
		const ready = createAsyncMemo((prev: boolean | null): Promise<boolean> => start());
		const [shown, setShown] = createSignal<boolean>(false);
		createRenderEffect<boolean>((prev: boolean | null): boolean => ready(), (value: boolean): Cleanup | null => { setShown(value); return null; });
		Show({ when: shown, children: mount })(host, parent, before);
	};
}
