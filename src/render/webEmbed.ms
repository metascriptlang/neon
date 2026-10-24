import { WebRule } from "./web";

export const IMAGE_TAG = "img";
export const IMAGE_CLASS = "neon-image";
export const BLUR_PREFIX = "neon-blur-";
export const TILE_PREFIX = "neon-tile-";

export function svgPrefix(count: int32): string {
	return `neon-svg${count}`;
}

export function blurRule(radius: string): WebRule | null {
	const px = parseFloat(radius);
	if (!(px > 0)) { return null; }
	const id = `${BLUR_PREFIX}${Math.round(px * 10)}`;
	return { id: id, css: `.${id}{filter:blur(${px}px)}` };
}

function cssString(text: string): string {
	return text.split("\\").join("\\\\").split("\"").join("\\\"").split("\n").join("\\a ").split("<").join("\\3c ");
}

// A tile's class comes from its source, so the page and the browser name the same picture alike
// and a class on a served image never means another source. Two sources that hash alike share a
// class: the browser host refuses that at the second one.
function sourceKey(src: string): string {
	let h: int64 = 5381;
	for (let i = 0; i < src.length; i += 1) { h = (h * 33 + src.charCodeAt(i)) % 4294967296; }
	return h.toString();
}

export function tileRule(src: string): WebRule {
	const id = `${TILE_PREFIX}${sourceKey(src)}`;
	return { id: id, css: `.${id}{background-image:url("${cssString(src)}");background-repeat:repeat;object-position:-100000px 0}` };
}
