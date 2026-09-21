// Context — createContext/useContext on the owner walk. A provider is a
// transparent scope (Solid's createProvider): its node carries the context
// entry and wraps the mount of its children, so consumers walk owner.owner
// upward and the nearest enclosing provider wins; identity is the context
// object itself. The entry stores the value thunk: every consumer read calls
// it, so signals inside the value track per consumer — no re-render, the
// Solid semantics our core already runs on.

import { Accessor } from "../core/signal";
import { Computation, CompState } from "../core/types";
import { getOwner } from "../core/runtime";
import { runWithOwner } from "../core/owner";
import { Host, HostNode, NeonNode } from "./hostTypes";

export interface ProviderProps<T> {
	value: Accessor<T>;
	children: NeonNode;
}

export interface Context<T> {
	defaultValue: T;
	Provider: (props: ProviderProps<T>) => NeonNode;
}

function noop(): void {}

export function useContext<T>(ctx: Context<T>): T {
	const key: unknown = ctx;
	let o = getOwner();
	while (o !== null) {
		const entries = o.contexts;
		if (entries !== null) {
			for (let i = 0; i < entries.length; i = i + 1) {
				if (entries[i].key === key) { return entries[i].read() as T; }
			}
		}
		o = o.owner;
	}
	return ctx.defaultValue;
}

function provideScope<T>(ctx: Context<T>, read: () => T, body: () => number): number {
	const parent = getOwner();
	const scope: Computation = {
		observers: [], observerSlots: [],
		fn: noop, isRoot: false, state: CompState.Clean,
		sources: [], sourceSlots: [],
		pure: false, disposed: false,
		owned: [], cleanups: [], owner: parent, contexts: [{ key: ctx as unknown, read: read as () => unknown }], handler: null,
	};
	if (parent !== null) { parent.owned.push(scope); }
	return runWithOwner(scope, body);
}

export function createContext<T>(defaultValue: T): Context<T> {
	const ctx: Context<T> = { defaultValue: defaultValue, Provider: null as (props: ProviderProps<T>) => NeonNode };
	ctx.Provider = (props: ProviderProps<T>): NeonNode => {
		return (host: Host, parent: HostNode, before: HostNode | null): void => {
			provideScope<T>(ctx, props.value, (): number => { props.children(host, parent, before); return 0; });
		};
	};
	return ctx;
}
