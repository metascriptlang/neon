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

class Provided<T> {
	read: () => T;
	constructor(read: () => T) { this.read = read; }
}

function noop(): void {}

export function useContext<T>(ctx: Context<T>): T {
	const key: unknown = ctx;
	const owner = getOwner();
	let entry = owner !== null ? owner.context : null;
	while (entry !== null) {
		if (entry.key === key) { return (entry.value as Provided<T>).read(); }
		entry = entry.next;
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
		owned: [], cleanups: [], owner: parent, context: { key: ctx as unknown, value: new Provided<T>(read), next: parent !== null ? parent.context : null }, handler: null,
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
