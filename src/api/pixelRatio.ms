import { usePixelRatio, useFontScale } from "./dimensions";

// RN's PixelRatio, over the scale the host published.
export class PixelRatio {
	static get(): number {
		return usePixelRatio()();
	}

	static getFontScale(): number {
		return useFontScale()();
	}

	static getPixelSizeForLayoutSize(layoutSize: number): number {
		return Math.round(layoutSize * PixelRatio.get());
	}

	static roundToNearestPixel(layoutSize: number): number {
		const ratio = PixelRatio.get();
		return Math.round(layoutSize * ratio) / ratio;
	}
}
