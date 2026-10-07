import { createContext } from "./context";

export enum VoidSpace {
	Outside,
	Area,
	Scene3D,
	Scene2D,
}

export const voidScope = createContext<VoidSpace>(VoidSpace.Outside);
