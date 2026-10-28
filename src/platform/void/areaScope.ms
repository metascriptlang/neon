import { Context, createContext } from "../../render/context";
import { AreaLayer } from "../../render/voidAreaHandle";
import { RenderTarget } from "../../../../void/src/gpu/target";
import { FontId, DEFAULT_FONT } from "../../../../void/src/void2d/font";

export interface AreaFace {
	font: FontId;
	family: string | null;
}

export interface AreaTarget {
	target: RenderTarget;
	drawers: AreaLayer[];
}

let faceContext: Context<AreaFace> | null = null;

export function getAreaFaceContext(): Context<AreaFace> {
	const existing = faceContext;
	if (existing !== null) { return existing; }
	const context = createContext<AreaFace>({ font: DEFAULT_FONT, family: null });
	faceContext = context;
	return context;
}

let targetContext: Context<AreaTarget | null> | null = null;

export function getAreaTargetContext(): Context<AreaTarget | null> {
	const existing = targetContext;
	if (existing !== null) { return existing; }
	const context = createContext<AreaTarget | null>(null);
	targetContext = context;
	return context;
}
