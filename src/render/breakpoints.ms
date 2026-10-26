import { Style, StyleBlock, emptyStyle, mergeStyle, installMediaLayering } from "./style";
import { Host, HostNode } from "./hostTypes";
import { bindStyleAll, installMediaBinding } from "./bind";
import { mediaWidth } from "./environment";
import { mergeStyleBody } from "../macros/style/fields";

export function createBreakpoints<T>(table: T): T {
	return table;
}

mergeStyleBody("block");
mergeStyleBody("mask");

export function resolveMedia(s: Style, width: number): Style {
	const blocks = s.media;
	if (blocks === null) { return s; }
	let acc = mergeStyle(emptyStyle(), s);
	acc.media = null;
	for (const block of blocks as StyleBlock[]) {
		if (width >= block.fromWidth) { acc = mergeBlock(acc, block); }
	}
	return acc;
}

function layerMedia(base: Style, over: Style): StyleBlock[] {
	const out: StyleBlock[] = [];
	for (const block of base.media as StyleBlock[]) { out.push(maskBlock(block, over)); }
	const above = over.media;
	if (above !== null) {
		for (const block of above as StyleBlock[]) { out.push(block); }
	}
	return out;
}

installMediaLayering(layerMedia);
installMediaBinding(
	(host: Host, node: HostNode, s: Style): void => { bindStyleAll(host, node, (): Style => s); },
	(s: Style): Style => resolveMedia(s, mediaWidth()),
);
