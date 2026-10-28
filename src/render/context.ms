import { Accessor } from "../core/signal";
import { getOwner, createOwner } from "../core/runtime";
import { runWithOwner } from "../core/owner";
import { Host, HostNode, NeonNode } from "./hostTypes";

export class NoOwnerError extends Error {
	constructor() { super("Context can only be accessed under a reactive root."); }
}

export class ContextNotFoundError extends Error {
	constructor() { super("Context must either be created with a default value or a value must be provided before accessing it."); }
}

class ContextKey {}

class Held<T> {
	value: T;
	constructor(value: T) { this.value = value; }
}

export interface Context<T> {
	key: ContextKey;
	fallback: Held<T> | null;
	provider: (props: { value: Accessor<T>; children: NeonNode }) => NeonNode;
}

export function useContext<T>(ctx: Context<T>): T {
	const owner = getOwner();
	if (owner === null) { throw new NoOwnerError(); }
	let entry = owner.context;
	while (entry !== null) {
		if (entry.key === ctx.key) { return (entry.value as Held<T>).value; }
		entry = entry.next;
	}
	const fallback = ctx.fallback;
	if (fallback === null) { throw new ContextNotFoundError(); }
	return fallback.value;
}

export function setContext<T>(ctx: Context<T>, value: T): void {
	const owner = getOwner();
	if (owner === null) { throw new NoOwnerError(); }
	owner.context = { key: ctx.key, value: new Held<T>(value), next: owner.context };
}

function newContext<T>(fallback: Held<T> | null): Context<T> {
	const key = new ContextKey();
	return {
		key: key,
		fallback: fallback,
		provider: (props: { value: Accessor<T>; children: NeonNode }): NeonNode => {
			return (host: Host, parent: HostNode, before: HostNode | null): void => {
				const scope = createOwner();
				runWithOwner(scope, (): number => {
					scope.context = { key: key, value: new Held<T>(props.value()), next: scope.context };
					props.children(host, parent, before);
					return 0;
				});
			};
		},
	};
}

export function createContext<T>(): Context<T> {
	return newContext<T>(null);
}

export function createContext<T>(defaultValue: T): Context<T> {
	return newContext<T>(new Held<T>(defaultValue));
}
