// Context — createContext/useContext on the owner walk. A provider is a
// transparent scope (Solid's createProvider): its scope registers a typed
// slot in the context object and wraps the mount of its children, so
// consumers walk owner.owner upward and the nearest enclosing provider wins;
// identity is the context object itself. The slot stores the value thunk:
// every consumer read calls it, so signals inside the value track per
// consumer — no re-render, the Solid semantics our core already runs on.
// The value stays typed T on the Context: core never erases it to unknown.

import { Accessor } from "../core/signal";
import { Computation, CompState } from "../core/types";
import { getOwner } from "../core/runtime";
import { runWithOwner } from "../core/owner";
import { Host, HostNode, NeonNode } from "./hostTypes";

export interface ProviderProps<T> {
	value: Accessor<T>;
	children: NeonNode;
}

export interface ProviderSlot<T> {
	owner: Computation;
	read: () => T;
}

export interface Context<T> {
	defaultValue: T;
	slots: ProviderSlot<T>[];
	Provider: (props: ProviderProps<T>) => NeonNode;
}

function noop(): void {}

export function useContext<T>(ctx: Context<T>): T {
	let o = getOwner();
	while (o !== null) {
		const slots = ctx.slots;
		for (let i = 0; i < slots.length; i = i + 1) {
			if (slots[i].owner === o) { return slots[i].read(); }
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
		owned: [], cleanups: [], owner: parent, handler: null,
	};
	const slot: ProviderSlot<T> = { owner: scope, read: read };
	ctx.slots.push(slot);
	scope.cleanups.push((): void => {
		const slots = ctx.slots;
		for (let i = 0; i < slots.length; i = i + 1) {
			if (slots[i] === slot) {
				slots[i] = slots[slots.length - 1];
				slots.pop();
				return;
			}
		}
	});
	if (parent !== null) { parent.owned.push(scope); }
	return runWithOwner(scope, body);
}

export function createContext<T>(defaultValue: T): Context<T> {
	const ctx: Context<T> = { defaultValue: defaultValue, slots: [], Provider: null as (props: ProviderProps<T>) => NeonNode };
	ctx.Provider = (props: ProviderProps<T>): NeonNode => {
		return (host: Host, parent: HostNode, before: HostNode | null): void => {
			provideScope<T>(ctx, props.value, (): number => { props.children(host, parent, before); return 0; });
		};
	};
	return ctx;
}
