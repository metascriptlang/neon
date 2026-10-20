import { createContext } from "./context";
import { VoidArea } from "./hostTypes";

export enum VoidSpace {
	Outside,
	Area,
	Scene3D,
	Scene2D,
}

export const voidScope = createContext<VoidSpace>(VoidSpace.Outside);
export const voidArea = createContext<VoidArea | null>(null);
