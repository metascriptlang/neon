import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { ScrollView, ScrollViewHandle, View } from "../../src/components/primitives";
import { sleepAsync } from "std/core/promise";

extern class HTMLElement {
	tagName: string;
	scrollTop: number;
	scrollHeight: number;
	clientHeight: number;
	firstChild: HTMLElement;
	extern remove(): void;
}

function probe(n: HostNode): HTMLElement {
	return n as unknown as HTMLElement;
}

function rows(): NeonNode {
	return element(<View>
		<View style={{ height: 50 }} /><View style={{ height: 50 }} /><View style={{ height: 50 }} /><View style={{ height: 50 }} />
		<View style={{ height: 50 }} /><View style={{ height: 50 }} /><View style={{ height: 50 }} /><View style={{ height: 50 }} />
	</View>);
}

test "ScrollView is a div that scrolls its own overflow" {
	const handles: ScrollViewHandle[] = [];
	render(element(<ScrollView style={{ height: 100 }} ref={(x: ScrollViewHandle): void => { handles.push(x); }}>{rows()}</ScrollView>), domHost(), documentBody());
	const el = probe(handles[0].node);
	assert el.tagName === "DIV", "tag " + el.tagName;
	assert el.clientHeight === 100, "viewport " + el.clientHeight.toString();
	assert el.scrollHeight === 400, "content " + el.scrollHeight.toString();
	el.scrollTop = 30;
	assert el.scrollTop === 30, "the div scrolls: " + el.scrollTop.toString();
	el.remove();
}

test "scrollTo moves the content offset" {
	const handles: ScrollViewHandle[] = [];
	render(element(<ScrollView style={{ height: 100 }} ref={(x: ScrollViewHandle): void => { handles.push(x); }}>{rows()}</ScrollView>), domHost(), documentBody());
	handles[0].scrollTo({ y: 120, animated: false });
	assert probe(handles[0].node).scrollTop === 120, "offset " + probe(handles[0].node).scrollTop.toString();
	probe(handles[0].node).remove();
}

test "onScroll reports React Native's offset, viewport and content size" {
	const handles: ScrollViewHandle[] = [];
	let got = "";
	render(element(<ScrollView style={{ height: 100, width: 200 }} ref={(x: ScrollViewHandle): void => { handles.push(x); }} onScroll={(e: NeonEvent): void => {
		got = `${e.type} ${e.y} ${e.width} ${e.height} ${e.contentHeight}`;
	}}>{rows()}</ScrollView>), domHost(), documentBody());
	handles[0].scrollTo({ y: 120, animated: false });
	await sleepAsync(100);
	assert got === "scroll 120 200 100 400", "payload: " + got;
	probe(handles[0].node).remove();
}
