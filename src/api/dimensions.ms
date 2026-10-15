import { Accessor, accessor, batch, createSignal } from "../core/signal";
import { useWindowDimensions } from "../render/environment";
import { EventSubscription, onChange } from "./subscription";

export interface ScaledSize {
	width: number;
	height: number;
	scale: number;
	fontScale: number;
}

export interface DimensionsChange {
	window: ScaledSize;
	screen: ScaledSize;
}

export type DimensionsKey = "window" | "screen";

const [pixelRatio, setPixelRatio] = createSignal<number>(1);
const [fontScale, setFontScale] = createSignal<number>(1);
const [screenWidth, setScreenWidth] = createSignal<number>(0);
const [screenHeight, setScreenHeight] = createSignal<number>(0);

export function publishScale(ratio: number, font: number): void {
	batch((): void => {
		if (pixelRatio() !== ratio) { setPixelRatio(ratio); }
		if (fontScale() !== font) { setFontScale(font); }
	});
}

export function publishScreen(width: number, height: number): void {
	batch((): void => {
		if (screenWidth() !== width) { setScreenWidth(width); }
		if (screenHeight() !== height) { setScreenHeight(height); }
	});
}

export function usePixelRatio(): Accessor<number> {
	return pixelRatio;
}

export function useFontScale(): Accessor<number> {
	return fontScale;
}

function windowSize(): ScaledSize {
	const window = useWindowDimensions()();
	return {
		width: window.width,
		height: window.height,
		scale: pixelRatio(),
		fontScale: fontScale(),
	};
}

function screenSize(): ScaledSize {
	const window = useWindowDimensions()();
	const width = screenWidth() > 0 ? screenWidth() : window.width;
	const height = screenHeight() > 0 ? screenHeight() : window.height;
	return { width, height, scale: pixelRatio(), fontScale: fontScale() };
}

const both: Accessor<DimensionsChange> = accessor((): DimensionsChange => ({
	window: windowSize(),
	screen: screenSize(),
}));

export class Dimensions {
	static get(dim: DimensionsKey): ScaledSize {
		return dim === "screen" ? screenSize() : windowSize();
	}

	static addEventListener(
		type: "change",
		handler: (change: DimensionsChange) => void,
	): EventSubscription {
		return onChange(both, handler);
	}
}
