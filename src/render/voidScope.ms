import { createContext } from "./context";
import { AreaHub } from "./voidAreaHandle";

export enum VoidSpace {
	Outside,
	Area,
	Scene3D,
	Scene2D,
}

export const voidScope = createContext<VoidSpace>(VoidSpace.Outside);
export const voidAreaHub = createContext<AreaHub | null>(null);
