import { createRoot } from "../../src/core/owner";
import { element } from "../../src/macros/ui/element";
import { neonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEvent, fireEventWith, fireTouch } from "../../src/render/host";
import { View, Text } from "../../src/components/primitives";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";
import {
	PageController,
	PageIndicator,
	PageRenderItemInfo,
	PageScrollState,
	PageView,
	pageDelta,
	pageIndex,
	pageTarget,
} from "../../src/components/pageView";

function mount(app: () => NeonNode): MockNode {
	const root = mockNode("root");
	createRoot((): void => { render(app(), mockHost(), root as unknown as HostNode); });
	return root;
}

function laidOut(n: MockNode, width: number, height: number): void {
	const e = neonEvent("layout");
	e.width = width;
	e.height = height;
	fireEventWith(n, "onLayout", e);
}

function transformOf(n: MockNode): string {
	const s = n.style;
	if (s === null) { return "none"; }
	return s.transform ?? "none";
}

function shown(n: MockNode): boolean {
	const s = n.style;
	return s === null || s.display !== "none";
}

function tagged(n: MockNode, tag: string): MockNode[] {
	const out: MockNode[] = [];
	for (const k of n.children) {
		if (k.tag === tag) { out.push(k); }
	}
	return out;
}

function drag(target: MockNode, points: number[], step: number, vertical: boolean): void {
	let t = 1000.0;
	const at = (name: string, p: number): void => {
		if (vertical) { fireTouch(target, name, 10, p, t); } else { fireTouch(target, name, p, 10, t); }
	};
	at("onTouchStart", points[0]);
	for (let i = 1; i < points.length; i += 1) {
		t += step;
		at("onTouchMove", points[i]);
	}
	t += Math.min(step, 10);
	at("onTouchEnd", points[points.length - 1]);
}

function labels(): string[] {
	return ["one", "two", "three", "four"];
}

function pager(log: string[], controller: PageController, loop: boolean, fraction: number): NeonNode {
	return element(<PageView data={labels()} controller={controller} loop={loop} viewportFraction={fraction}
		onPageSelected={(i: number): void => { log.push("page " + i.toString()); }}
		onPageScrollStateChanged={(s: PageScrollState): void => { log.push(s); }}
		renderItem={(info: PageRenderItemInfo<string>): NeonNode => <View style={{ flex: 1 }}><Text>{info.item}</Text></View>} />);
}

test "a fling rounds half a page towards its direction, a slow release to the nearest page" {
	assert pageTarget(0.3, 0) === 0 && pageTarget(0.6, 0) === 1, "nearest";
	assert pageTarget(0.1, 60) === 1 && pageTarget(0.9, -60) === 0, "fling past 50 px/s";
	assert pageTarget(0.1, 40) === 0, "a slow release is not a fling";
	assert pageIndex(-1, 4, true) === 3 && pageIndex(5, 4, true) === 1 && pageIndex(9, 4, false) === 3, "wrap and clamp";
	assert pageDelta(3, 0, 4, true) === -1 && pageDelta(3, 0, 4, false) === 3, "a loop takes the short way round";
}

test "a drag past half a page settles on the next page and reports it once" {
	const clock = useManualFrames();
	const log: string[] = [];
	const controller = new PageController(0);
	const root = mount((): NeonNode => pager(log, controller, false, 1));
	const outer = root.children[0];
	laidOut(outer, 300, 400);
	assert transformOf(outer.children[0]) === "translateX(0px)" && transformOf(outer.children[1]) === "translateX(300px)", transformOf(outer.children[1]);
	assert !shown(outer.children[2]), "a page two pages away is not displayed";
	drag(outer.children[0].children[0], [250, 230, 180, 120, 60], 100, false);
	clock.runAll();
	assert log.join(",") === "dragging,page 1,settling,idle", log.join(",");
	assert controller.peek() === 1 && controller.selectedPage() === 1, "settled on page 1";
	assert transformOf(outer.children[1]) === "translateX(0px)" && transformOf(outer.children[0]) === "translateX(-300px)", transformOf(outer.children[0]);
	setFrameDriver(null);
}

test "a short fast fling turns the page, a short slow drag springs back" {
	const clock = useManualFrames();
	const log: string[] = [];
	const controller = new PageController(0);
	const root = mount((): NeonNode => pager(log, controller, false, 1));
	const outer = root.children[0];
	laidOut(outer, 300, 400);
	drag(outer.children[0], [250, 230, 200], 10, false);
	clock.runAll();
	assert controller.selectedPage() === 1, "the fling went to page 1: " + log.join(",");
	drag(outer.children[1], [100, 112, 124, 136, 136], 100, false);
	clock.runAll();
	assert controller.selectedPage() === 1 && controller.peek() === 1, "a slow 36 pt drag stays on page 1";
	let t = 5000.0;
	fireTouch(outer.children[1], "onTouchStart", 100, 10, t);
	fireTouch(outer.children[1], "onTouchMove", 115, 10, t + 10);
	fireTouch(outer.children[1], "onTouchMove", 160, 10, t + 20);
	fireTouch(outer.children[1], "onTouchEnd", 160, 10, t + 320);
	clock.runAll();
	assert controller.selectedPage() === 1, "a fast drag that rests before lifting does not fling";
	setFrameDriver(null);
}

test "dragging past the first page resists and springs back" {
	const clock = useManualFrames();
	const log: string[] = [];
	const controller = new PageController(0);
	const root = mount((): NeonNode => pager(log, controller, false, 1));
	const outer = root.children[0];
	laidOut(outer, 300, 400);
	let t = 1000.0;
	fireTouch(outer.children[0], "onTouchStart", 50, 10, t);
	fireTouch(outer.children[0], "onTouchMove", 80, 10, t + 100);
	fireTouch(outer.children[0], "onTouchMove", 150, 10, t + 200);
	assert Math.abs(controller.peek() + 70.0 / 300.0 * 0.35) < 0.001, "the edge moves a share of the finger: " + controller.peek().toString();
	fireTouch(outer.children[0], "onTouchEnd", 150, 10, t + 300);
	clock.runAll();
	assert controller.peek() === 0 && log.indexOf("page 3") < 0, "back on the first page: " + log.join(",");
	setFrameDriver(null);
}

test "setPage animates to its target and reports only the target" {
	const clock = useManualFrames();
	const log: string[] = [];
	const controller = new PageController(0);
	const root = mount((): NeonNode => pager(log, controller, false, 1));
	laidOut(root.children[0], 300, 400);
	controller.setPage(3);
	clock.step(5);
	assert controller.selectedPage() === 3 && controller.peek() > 0 && controller.peek() < 3, "selected at once, still moving";
	clock.runAll();
	assert controller.peek() === 3 && log.join(",") === "page 3,settling,idle", log.join(",");
	controller.setPageWithoutAnimation(0);
	assert controller.peek() === 0 && log.join(",") === "page 3,settling,idle,page 0", log.join(",");
	controller.setPage(9);
	clock.runAll();
	assert controller.peek() === 3, "a page past the end clamps";
	setFrameDriver(null);
}

test "a looping pager goes from the first page back to the last one" {
	const clock = useManualFrames();
	const log: string[] = [];
	const controller = new PageController(0);
	const root = mount((): NeonNode => pager(log, controller, true, 1));
	const outer = root.children[0];
	laidOut(outer, 300, 400);
	assert transformOf(outer.children[3]) === "translateX(-300px)", "the last page waits on the left: " + transformOf(outer.children[3]);
	drag(outer.children[0], [50, 80, 130, 200, 230], 100, false);
	clock.runAll();
	assert controller.selectedPage() === 3 && controller.peek() === -1, "on the last page through the loop: " + log.join(",");
	assert transformOf(outer.children[3]) === "translateX(0px)", transformOf(outer.children[3]);
	controller.setPage(0);
	clock.runAll();
	assert controller.peek() === 0, "setPage takes the short way round: " + controller.peek().toString();
	setFrameDriver(null);
}

test "a viewport fraction centres the page and lets the neighbours peek" {
	const log: string[] = [];
	const controller = new PageController(1);
	const root = mount((): NeonNode => pager(log, controller, false, 0.8));
	const outer = root.children[0];
	laidOut(outer, 300, 400);
	const page = outer.children[1].style;
	assert page !== null && page.width === 240, "a page is 80% of the viewport";
	assert transformOf(outer.children[1]) === "translateX(30px)", transformOf(outer.children[1]);
	assert transformOf(outer.children[0]) === "translateX(-210px)" && shown(outer.children[0]), "the previous page peeks";
	assert transformOf(outer.children[2]) === "translateX(270px)" && shown(outer.children[2]), "the next page peeks";
}

test "a vertical pager pages on the vertical axis" {
	const clock = useManualFrames();
	const log: string[] = [];
	const controller = new PageController(0);
	const root = mount((): NeonNode => element(<PageView data={labels()} controller={controller} orientation="vertical"
		renderItem={(info: PageRenderItemInfo<string>): NeonNode => <Text>{info.item}</Text>} />));
	const outer = root.children[0];
	laidOut(outer, 300, 400);
	assert transformOf(outer.children[1]) === "translateY(400px)", transformOf(outer.children[1]);
	drag(outer.children[0], [350, 300, 200, 120], 100, true);
	clock.runAll();
	assert controller.selectedPage() === 1, "paged down";
	drag(outer.children[1], [100, 120, 300], 100, false);
	clock.runAll();
	assert controller.selectedPage() === 1, "a horizontal drag does not page a vertical pager";
	setFrameDriver(null);
}

test "the page indicator widens the selected dot and reports a press" {
	const presses: number[] = [];
	const controller = new PageController(2);
	const root = mount((): NeonNode => element(<PageIndicator count={4} page={controller.page()}
		onPress={(i: number): void => { presses.push(i); }} />));
	const dots = tagged(root.children[0], "pressable");
	assert dots.length === 4, "four dots: " + mockToString(root);
	const active = dots[2].style;
	const idle = dots[0].style;
	assert active !== null && idle !== null && active.width === 20 && idle.width === 8, "the selected dot is wider";
	fireEvent(dots[1], "onPress");
	assert presses.join(",") === "1", presses.join(",");
}
