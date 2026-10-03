import { createRoot } from "../../src/core/owner";
import { element } from "../../src/macros/ui/element";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent, fireEventWith } from "../../src/render/host";
import { ScrollView, ScrollViewHandle, Text, Pressable } from "../../src/components/primitives";

function scrollEvent(x: number, y: number, width: number, height: number, contentWidth: number, contentHeight: number): NeonEvent {
	const e = neonEvent("scroll");
	e.x = x;
	e.y = y;
	e.width = width;
	e.height = height;
	e.contentWidth = contentWidth;
	e.contentHeight = contentHeight;
	return e;
}

test "ScrollView mounts a scroll container around a content container" {
	const root: MockNode = mockNode("root");
	render(element(<ScrollView><Text>a</Text><Text>b</Text></ScrollView>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><scrollview><view><text>a</text><text>b</text></view></scrollview></root>", mockToString(root);
}

test "style goes to the scroll container, contentContainerStyle to the content" {
	const root: MockNode = mockNode("root");
	render(element(<ScrollView style={{ flexGrow: 1 }} contentContainerStyle={{ padding: 8 }}><Text>a</Text></ScrollView>), mockHost(), root as unknown as HostNode);
	const sv = root.children[0];
	assert sv.style !== null && sv.style!.flexGrow === 1, "flexGrow on the scroll container";
	const content = sv.children[0];
	assert content.style !== null && content.style!.padding === 8, "padding on the content container";
}

test "a ScrollView grows and shrinks in its parent unless its style says otherwise, React Native's base style" {
	const root: MockNode = mockNode("root");
	render(element(<ScrollView><Text>a</Text></ScrollView>), mockHost(), root as unknown as HostNode);
	const sv = root.children[0];
	assert sv.style !== null, "the scroll container carries the base style";
	assert sv.style!.flexGrow === 1 && sv.style!.flexShrink === 1, "base flexGrow and flexShrink: " + `${sv.style!.flexGrow} ${sv.style!.flexShrink}`;
	assert sv.style!.flexDirection === "column" && sv.style!.overflow === "scroll", "base flexDirection column and overflow scroll";
	const root2: MockNode = mockNode("root");
	render(element(<ScrollView style={{ flexGrow: 0, height: 100 }}><Text>a</Text></ScrollView>), mockHost(), root2 as unknown as HostNode);
	const sv2 = root2.children[0];
	assert sv2.style!.flexGrow === 0 && sv2.style!.flexShrink === 1, "the author's flexGrow wins, flexShrink stays: " + `${sv2.style!.flexGrow} ${sv2.style!.flexShrink}`;
	assert (sv2.style!.height as number) === 100, "the author's height is kept";
}

test "onContentSizeChange receives the content container's size, React Native's _handleContentOnLayout" {
	const root: MockNode = mockNode("root");
	let got = "";
	render(element(<ScrollView onContentSizeChange={(width: number, height: number): void => { got = `${width} ${height}`; }}><Text>a</Text></ScrollView>), mockHost(), root as unknown as HostNode);
	const sized = neonEvent("layout");
	sized.width = 320;
	sized.height = 2000;
	fireEventWith(root.children[0].children[0], "onLayout", sized);
	assert got === "320 2000", "content size: " + got;
}

test "onScroll receives the content offset, the viewport and the content size" {
	const root: MockNode = mockNode("root");
	let got = "";
	render(element(<ScrollView onScroll={(e: NeonEvent): void => {
		got = `${e.type} ${e.x} ${e.y} ${e.width} ${e.height} ${e.contentWidth} ${e.contentHeight}`;
	}}><Text>a</Text></ScrollView>), mockHost(), root as unknown as HostNode);
	fireEventWith(root.children[0], "onScroll", scrollEvent(0, 120, 320, 480, 320, 2000));
	assert got === "scroll 0 120 320 480 320 2000", "payload: " + got;
}

test "without scrollEventThrottle every scroll event reaches onScroll" {
	const root: MockNode = mockNode("root");
	let calls = 0;
	render(element(<ScrollView onScroll={(e: NeonEvent): void => { calls = calls + 1; }}><Text>a</Text></ScrollView>), mockHost(), root as unknown as HostNode);
	const sv = root.children[0];
	fireEventWith(sv, "onScroll", scrollEvent(0, 1, 320, 480, 320, 2000));
	fireEventWith(sv, "onScroll", scrollEvent(0, 2, 320, 480, 320, 2000));
	fireEventWith(sv, "onScroll", scrollEvent(0, 3, 320, 480, 320, 2000));
	assert calls === 3, "calls " + calls.toString();
}

test "scrollEventThrottle drops events closer together than the interval" {
	const root: MockNode = mockNode("root");
	let seen = "";
	render(element(<ScrollView scrollEventThrottle={60000} onScroll={(e: NeonEvent): void => { seen = seen + `${e.y};`; }}><Text>a</Text></ScrollView>), mockHost(), root as unknown as HostNode);
	const sv = root.children[0];
	fireEventWith(sv, "onScroll", scrollEvent(0, 1, 320, 480, 320, 2000));
	fireEventWith(sv, "onScroll", scrollEvent(0, 2, 320, 480, 320, 2000));
	assert seen === "1;", "only the first event inside the interval: " + seen;
}

test "the ref receives a handle whose scrollTo reaches the host" {
	const root: MockNode = mockNode("root");
	const handles: ScrollViewHandle[] = [];
	render(element(<ScrollView ref={(x: ScrollViewHandle): void => { handles.push(x); }}><Text>a</Text></ScrollView>), mockHost(), root as unknown as HostNode);
	const sv = root.children[0];
	assert handles.length === 1, "ref called once at mount";
	assert handles[0].node === (sv as unknown as HostNode), "the handle carries the scroll container node";
	handles[0].scrollTo({ y: 40 });
	assert `${sv.scrollX} ${sv.scrollY} ${sv.scrollAnimated}` === "0 40 true", "RN defaults x to 0 and animated to true";
	handles[0].scrollTo({ x: 5, y: 6, animated: false });
	assert `${sv.scrollX} ${sv.scrollY} ${sv.scrollAnimated}` === "5 6 false", "explicit options";
}

test "scrollTo after the ScrollView unmounted fails loud" {
	const root: MockNode = mockNode("root");
	const handles: ScrollViewHandle[] = [];
	const dispose = render(element(<ScrollView ref={(x: ScrollViewHandle): void => { handles.push(x); }}><Text>a</Text></ScrollView>), mockHost(), root as unknown as HostNode);
	dispose();
	let caught = "";
	try {
		handles[0].scrollTo({ y: 1 });
	} catch (e) { caught = e.toString(); }
	assert caught.includes("unmounted"), "names the unmount: " + caught;
}

test "scrollTo on a host without the capability fails loud" {
	const host = mockHost();
	host.scrollTo = null;
	const root: MockNode = mockNode("root");
	const handles: ScrollViewHandle[] = [];
	render(element(<ScrollView ref={(x: ScrollViewHandle): void => { handles.push(x); }}><Text>a</Text></ScrollView>), host, root as unknown as HostNode);
	let caught = "";
	try {
		handles[0].scrollTo({ y: 1 });
	} catch (e) { caught = e.toString(); }
	assert caught.includes("scrollTo capability"), "names the capability: " + caught;
}

test "a press the host cancels for a scroll does not fire onPress" {
	const root: MockNode = mockNode("root");
	let log = "";
	createRoot((): void => {
		render(element(<ScrollView onScroll={(e: NeonEvent): void => { log = log + "scroll;"; }}>
			<Pressable onPressIn={(e: NeonEvent): void => { log = log + "in;"; }} onPress={(e: NeonEvent): void => { log = log + "press;"; }}><Text>row</Text></Pressable>
		</ScrollView>), mockHost(), root as unknown as HostNode);
	});
	const sv = root.children[0];
	const row = sv.children[0].children[0];
	fireEvent(row, "onPointerDown");
	fireEvent(row, "onPointerCancel");
	fireEventWith(sv, "onScroll", scrollEvent(0, 30, 320, 480, 320, 2000));
	fireEvent(row, "onPointerUp");
	assert log === "in;scroll;", "no press after the cancel: " + log;
}
