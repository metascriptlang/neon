import { domHost, documentBody } from "../../src/platform/browser/dom";
import { NeonNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { Text, View } from "../../src/components/primitives";
import { SectionBase, SectionInfo, SectionList, SectionListRenderItemInfo } from "../../src/components/sectionList";
import { sleepAsync } from "std/core/promise";

extern class HTMLElement {
	scrollTop: number;
	lastElementChild: HTMLElement;
	extern querySelectorAll(selector: cstring): ElementList;
	extern getBoundingClientRect(): Frame;
	extern remove(): void;
}

extern class ElementList {
	length: number;
	extern item(index: int32): HTMLElement;
}

extern class Frame {
	top: number;
	height: number;
}

interface Item {
	n: number;
}

function sections(): SectionBase<Item>[] {
	const out: SectionBase<Item>[] = [];
	for (let s = 0; s < 3; s += 1) {
		const data: Item[] = [];
		for (let i = 0; i < 5; i += 1) { data.push({ n: s * 10 + i }); }
		out.push({ key: "s" + s.toString(), data });
	}
	return out;
}

test "measured SectionList pins each section header until the next one pushes it out" {
	const dispose = render(element(<SectionList sections={sections()} style={{ height: 200 }} stickySectionHeadersEnabled={true}
		renderSectionHeader={(info: SectionInfo<SectionBase<Item>>): NeonNode =>
			<View class={"section-" + (info.section.key as string)} style={{ height: 30 }}><Text>{info.section.key as string}</Text></View>}
		renderItem={(info: SectionListRenderItemInfo<Item, SectionBase<Item>>): NeonNode =>
			<View style={{ height: 50 }}><Text>{"<" + info.item.n.toString() + ">"}</Text></View>} />), domHost(), documentBody());
	await sleepAsync(200);
	const scroller = (documentBody() as unknown as HTMLElement).lastElementChild;
	const top = scroller.getBoundingClientRect().top;
	scroller.scrollTop = 100;
	await sleepAsync(150);
	assert scroller.querySelectorAll(".section-s0").item(0).getBoundingClientRect().top === top, "the first header sticks inside its section";
	scroller.scrollTop = 300;
	await sleepAsync(150);
	const second = scroller.querySelectorAll(".section-s1").item(0).getBoundingClientRect();
	assert second.top === top, "the second header takes over: " + `${second.top} ${top}`;
	dispose();
	scroller.remove();
}
