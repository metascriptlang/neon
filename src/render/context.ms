import { Accessor } from "../core/signal";
import { getOwner, createOwner } from "../core/runtime";
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
	const scope = createOwner();
	scope.context = { key: ctx as unknown, value: new Provided<T>(read), next: parent !== null ? parent.context : null };
	return runWithOwner(scope, body);
}

export function createContext<T>(defaultValue: T): Context<T> {
	const ctx: Context<T> = {
		defaultValue: defaultValue,
		Provider: (props: ProviderProps<T>): NeonNode => props.children,
	};
	ctx.Provider = (props: ProviderProps<T>): NeonNode => {
		return (host: Host, parent: HostNode, before: HostNode | null): void => {
			provideScope<T>(ctx, props.value, (): number => { props.children(host, parent, before); return 0; });
		};
	};
	return ctx;
}
