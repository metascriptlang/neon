import { Context, NoOwnerError, createContext, useContext } from "./context";
import { getOwner } from "../core/runtime";
import { VoidArea } from "./hostTypes";

export enum VoidSpace {
	Outside,
	Area,
	Scene3D,
	Scene2D,
}

let scopeContext: Context<VoidSpace> | null = null;

export function getVoidScopeContext(): Context<VoidSpace> {
	const existing = scopeContext;
	if (existing !== null) { return existing; }
	const context = createContext<VoidSpace>(VoidSpace.Outside);
	scopeContext = context;
	return context;
}

export function useVoidSpace(): VoidSpace {
	if (getOwner() === null) { throw new NoOwnerError(); }
	const context = scopeContext;
	return context === null ? VoidSpace.Outside : useContext(context);
}
let areaContext: Context<VoidArea | null> | null = null;

export function getVoidAreaContext(): Context<VoidArea | null> {
	const existing = areaContext;
	if (existing !== null) { return existing; }
	const context = createContext<VoidArea | null>(null);
	areaContext = context;
	return context;
}
