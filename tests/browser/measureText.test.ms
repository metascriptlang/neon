import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View, ViewHandle, Text, ElementHandle } from "../../src/components/primitives";

extern class Frame {
	width: number;
	height: number;
}

extern class HTMLElement {
	extern remove(): void;
	extern getBoundingClientRect(): Frame;
}

function probe(n: HostNode): HTMLElement {
	return n as unknown as HTMLElement;
}

test "a View's handle measures a line as wide as the Text the page draws" {
	let frame: ViewHandle | null = null;
	let shown: HostNode | null = null;
	render(element(<View ref={(h: ViewHandle): void => { frame = h; }} style={{ alignItems: "flex-start" }}>
		<Text ref={(h: ElementHandle): void => { shown = h.node; }} style={{ fontFamily: "monospace", fontSize: 20 }}>MMMMMMMM</Text>
	</View>), domHost(), documentBody());
	const m = (frame as ViewHandle).measureText("MMMMMMMM", { fontFamily: "monospace", fontSize: 20 });
	const drawn = probe(shown as HostNode).getBoundingClientRect();
	assert Math.abs(m.width - drawn.width) < 1, `measured ${m.width}, drawn ${drawn.width}`;
	assert m.ascender > 0 && m.descender > 0 && m.height === m.ascender + m.descender, `line ${m.ascender}+${m.descender}=${m.height}`;
	const big = (frame as ViewHandle).measureText("MMMMMMMM", { fontFamily: "monospace", fontSize: 40 });
	assert Math.abs(big.width - 2 * m.width) < 1, `double size ${big.width} against ${m.width}`;
	probe((frame as ViewHandle).node).remove();
}
