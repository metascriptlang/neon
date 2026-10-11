import { createSignal } from "../../src/core/signal";
import { Dispose } from "../../src/core/types";
import { element } from "../../src/macros/ui/element";
import { neonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/node";
import { Style } from "../../src/render/style";
import { HostNode, MockNode, mockNode, mockHost, render, fireEvent, fireEventWith, fireTouch } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";
import { TabLayout, TabRoute, TabSceneInfo, TabView, indicatorAt } from "../../src/components/tabView";

let disposeLast: Dispose | null = null;

function mount(app: () => NeonNode): MockNode {
	const root = mockNode("root");
	disposeLast = render(app(), mockHost(), root as unknown as HostNode);
	return root;
}

function unmount(): void {
	if (disposeLast !== null) { (disposeLast as Dispose)(); }
	disposeLast = null;
	setFrameDriver(null);
}

function attrOf(n: MockNode, name: string): string {
	for (const a of n.attrs) {
		if (a.name === name) { return a.value ?? ""; }
	}
	return "";
}

function collect(n: MockNode, test: (m: MockNode) => boolean, out: MockNode[]): MockNode[] {
	if (test(n)) { out.push(n); }
	for (const k of n.children) { collect(k, test, out); }
	return out;
}

function texts(n: MockNode): string[] {
	const out: string[] = [];
	for (const m of collect(n, (m: MockNode): boolean => m.tag === "" && m.text !== "", [])) { out.push(m.text); }
	return out;
}

function tabs(root: MockNode): MockNode[] {
	return collect(root, (m: MockNode): boolean => attrOf(m, "accessibilityRole") === "tab", []);
}

function laidOut(n: MockNode, x: number, width: number, height: number): void {
	const e = neonEvent("layout");
	e.x = x;
	e.width = width;
	e.height = height;
	fireEventWith(n, "onLayout", e);
}

function pager(root: MockNode): MockNode {
	return collect(root, (m: MockNode): boolean => {
		for (const e of m.events) {
			if (e.name === "onTouchMove") { return true; }
		}
		return false;
	}, [])[0];
}

function indicator(root: MockNode): MockNode {
	return collect(root, (m: MockNode): boolean => m.style !== null && (m.style as Style).height === 2, [])[0];
}

function routes(): TabRoute[] {
	return [{ key: "chats", title: "Chats" }, { key: "status", title: "Status" }, { key: "calls", title: "Calls" }];
}

function scene(info: TabSceneInfo): NeonNode {
	return <Text>{"scene " + info.route.key}</Text>;
}

test "the indicator lies between the two tabs a fractional position falls between" {
	const layouts: TabLayout[] = [{ x: 0, width: 100 }, { x: 100, width: 60 }, { x: 160, width: 140 }];
	const half = indicatorAt(layouts, 0.5);
	assert half.x === 50 && half.width === 80, "half way: " + half.x.toString() + " " + half.width.toString();
	const end = indicatorAt(layouts, 2);
	assert end.x === 160 && end.width === 140;
	const over = indicatorAt(layouts, -0.3);
	assert over.x === 0 && over.width === 100, "clamped at the first tab";
}

test "a tab press moves the pages, the indicator and the selected state" {
	const clock = useManualFrames();
	const changes: number[] = [];
	const [index, setIndex] = createSignal<number>(0);
	const root = mount((): NeonNode => element(<TabView routes={routes()} index={index()} renderScene={scene}
		onIndexChange={(i: number): void => { changes.push(i); setIndex(i); }} />));
	const bar = tabs(root);
	assert bar.length === 3, "three tabs";
	laidOut(bar[0], 0, 100, 48);
	laidOut(bar[1], 100, 100, 48);
	laidOut(bar[2], 200, 100, 48);
	laidOut(pager(root), 0, 300, 500);
	assert attrOf(bar[0], "accessibilityState") === "selected", attrOf(bar[0], "accessibilityState");
	fireEvent(bar[2], "onPress");
	clock.step(9);
	const moving = indicator(root).style as Style;
	assert (moving.left as number) > 0 && (moving.left as number) < 200, "the indicator is on its way";
	clock.runAll();
	assert changes.join(",") === "2", "reported once: " + changes.join(",");
	assert (indicator(root).style as Style).left === 200, "under the third tab";
	assert attrOf(bar[2], "accessibilityState") === "selected" && attrOf(bar[0], "accessibilityState") === "", "selected moved";
	setIndex(1);
	clock.runAll();
	assert (indicator(root).style as Style).left === 100 && changes.join(",") === "2", "a controlled index moves without echo";
	unmount();
}

test "a swipe changes the index and drags the indicator along" {
	const clock = useManualFrames();
	const changes: number[] = [];
	const root = mount((): NeonNode => element(<TabView routes={routes()} renderScene={scene}
		onIndexChange={(i: number): void => { changes.push(i); }} />));
	const bar = tabs(root);
	laidOut(bar[0], 0, 100, 48);
	laidOut(bar[1], 100, 100, 48);
	laidOut(bar[2], 200, 100, 48);
	const pages = pager(root);
	laidOut(pages, 0, 300, 500);
	fireTouch(pages.children[0], "onTouchStart", 250, 100, 1000);
	fireTouch(pages.children[0], "onTouchMove", 230, 100, 1100);
	fireTouch(pages.children[0], "onTouchMove", 155, 100, 1200);
	assert (indicator(root).style as Style).left === 25, "a quarter page drag moves the indicator a quarter tab: " + ((indicator(root).style as Style).left as number).toString();
	fireTouch(pages.children[0], "onTouchMove", 50, 100, 1300);
	fireTouch(pages.children[0], "onTouchEnd", 50, 100, 1400);
	clock.runAll();
	assert changes.join(",") === "1" && (indicator(root).style as Style).left === 100, "on the second tab: " + changes.join(",");
	unmount();
}

test "lazy scenes mount when first focused and stay mounted" {
	const clock = useManualFrames();
	const root = mount((): NeonNode => element(<TabView routes={routes()} renderScene={scene} lazy={true}
		renderLazyPlaceholder={(r: TabRoute): NeonNode => <Text>{"loading " + r.key}</Text>} />));
	laidOut(pager(root), 0, 300, 500);
	const shown = texts(root).join(",");
	assert shown.indexOf("scene chats") >= 0 && shown.indexOf("loading status") >= 0 && shown.indexOf("scene status") < 0, shown;
	fireEvent(tabs(root)[1], "onPress");
	clock.runAll();
	assert texts(root).join(",").indexOf("scene status") >= 0, "the second scene rendered: " + texts(root).join(",");
	fireEvent(tabs(root)[0], "onPress");
	clock.runAll();
	assert texts(root).join(",").indexOf("scene status") >= 0 && texts(root).join(",").indexOf("loading calls") >= 0, "kept, and the third still waits";
	unmount();
}

test "a scrollable tab bar centres the selected tab" {
	const clock = useManualFrames();
	const many: TabRoute[] = [];
	for (let i = 0; i < 8; i += 1) { many.push({ key: "k" + i.toString(), title: "Tab " + i.toString() }); }
	const root = mount((): NeonNode => element(<TabView routes={many} renderScene={scene} scrollEnabled={true} />));
	const bar = tabs(root);
	for (let i = 0; i < 8; i += 1) { laidOut(bar[i], (i as number) * 90, 90, 48); }
	const scroller = collect(root, (m: MockNode): boolean => m.tag === "scrollview", [])[0];
	laidOut(scroller, 0, 300, 48);
	fireEvent(bar[5], "onPress");
	clock.runAll();
	assert scroller.scrollX === 345, "tab 5 centred: " + scroller.scrollX.toString();
	unmount();
}
