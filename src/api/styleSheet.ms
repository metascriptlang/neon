// RN StyleSheet's runtime members. `StyleSheet.create` is `createStyles` (src/macros/ui/style.ms):
// a macro cannot be a class member, and called through a namespace import it reaches codegen
// unexpanded (compiler card 2026-10-08-macro-called-through-namespace-import-reaches-codegen.md,
// WORKAROUND.md G3).

import { Style, layerStyles, mergeStyle } from "../render/style";
import { usePixelRatio } from "./dimensions";
import { onChange } from "./subscription";

// RN StyleSheet.js: the thinnest line the screen can draw, rounded to its pixel grid, and never 0.
function hairline(ratio: number): number {
	const width = Math.round(0.4 * ratio) / ratio;
	return width === 0 ? 1 / ratio : width;
}

const FILL: Style = { position: "absolute", left: 0, right: 0, top: 0, bottom: 0 };

export class StyleSheet {
	static hairlineWidth: number = hairline(usePixelRatio()());
	static absoluteFill: Style = FILL;
	static absoluteFillObject: Style = FILL;

	// RN flatten: later entries win field by field; null entries (RN's falsy) are skipped.
	static flatten(styles: (Style | null)[]): Style {
		const layers: Style[] = [{}];
		for (const s of styles) {
			if (s !== null) { layers.push(s as Style); }
		}
		return layerStyles(layers);
	}

	static compose(first: Style | null, second: Style | null): Style {
		if (first === null) { return second === null ? {} : second as Style; }
		if (second === null) { return first as Style; }
		return mergeStyle(first as Style, second as Style);
	}
}

onChange(usePixelRatio(), (ratio: number): void => { StyleSheet.hairlineWidth = hairline(ratio); });
