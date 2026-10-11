import { Dispose } from "../../src/core/types";
import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { neonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render, fireEventWith, fireTouch } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";
import { sleepAsync } from "std/core/promise";
import { PageController, PageRenderItemInfo } from "../../src/components/pageView";
import { Carousel, CarouselMode, parallaxScale } from "../../src/components/carousel";

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

function slides(): string[] {
	return ["red", "green", "blue"];
}

test "parallax shrinks a neighbour to the configured scale" {
	assert parallaxScale(0, 0.8) === 1 && Math.abs(parallaxScale(1, 0.8) - 0.8) < 0.0001 && Math.abs(parallaxScale(-3, 0.8) - 0.8) < 0.0001;
	assert Math.abs(parallaxScale(0.5, 0.8) - 0.9) < 0.0001;
}

test "auto-play advances each interval, loops past the last slide and reports each snap" {
	const clock = useManualFrames();
	const snaps: number[] = [];
	let controller: PageController | null = null;
	const root = mount((): NeonNode => element(<Carousel data={slides()} autoPlay={true} autoPlayInterval={20}
		ref={(c: PageController): void => { controller = c; }}
		onSnapToItem={(i: number): void => { snaps.push(i); }}
		renderItem={(info: PageRenderItemInfo<string>): NeonNode => <Text>{info.item}</Text>} />));
	laidOut(root.children[0], 300, 200);
	for (let i = 0; i < 3; i += 1) {
		await sleepAsync(60);
		clock.runAll();
	}
	assert snaps.join(",") === "1,2,0", "1, 2 and round to 0: " + snaps.join(",");
	assert (controller as PageController).peek() === 3, "the loop kept going forward: " + (controller as PageController).peek().toString();
	unmount();
}

test "a finger on the carousel holds auto-play until the drag ends" {
	const clock = useManualFrames();
	const snaps: number[] = [];
	const root = mount((): NeonNode => element(<Carousel data={slides()} autoPlay={true} autoPlayInterval={20}
		onSnapToItem={(i: number): void => { snaps.push(i); }}
		renderItem={(info: PageRenderItemInfo<string>): NeonNode => <Text>{info.item}</Text>} />));
	const outer = root.children[0];
	laidOut(outer, 300, 200);
	fireTouch(outer.children[0], "onTouchStart", 200, 10, 1000);
	fireTouch(outer.children[0], "onTouchMove", 180, 10, 1100);
	fireTouch(outer.children[0], "onTouchMove", 170, 10, 1200);
	await sleepAsync(80);
	clock.runAll();
	assert snaps.length === 0, "held: " + snaps.join(",");
	fireTouch(outer.children[0], "onTouchMove", 170, 10, 1300);
	fireTouch(outer.children[0], "onTouchEnd", 170, 10, 1400);
	clock.runAll();
	await sleepAsync(60);
	clock.runAll();
	assert snaps.join(",") === "1", "resumed after the release: " + snaps.join(",");
	unmount();
}

test "turning auto-play off stops the timer; without a loop auto-play stops at the end" {
	const clock = useManualFrames();
	const [playing, setPlaying] = createSignal(true);
	const snaps: number[] = [];
	const root = mount((): NeonNode => element(<Carousel data={slides()} autoPlay={playing()} autoPlayInterval={20} loop={false}
		onSnapToItem={(i: number): void => { snaps.push(i); }}
		renderItem={(info: PageRenderItemInfo<string>): NeonNode => <Text>{info.item}</Text>} />));
	laidOut(root.children[0], 300, 200);
	for (let i = 0; i < 4; i += 1) {
		await sleepAsync(60);
		clock.runAll();
	}
	assert snaps.join(",") === "1,2", "stopped at the last slide: " + snaps.join(",");
	setPlaying(false);
	await sleepAsync(60);
	clock.runAll();
	assert snaps.join(",") === "1,2";
	unmount();
}

test "parallax mode shrinks the peeking neighbours" {
	const mode: CarouselMode = "parallax";
	const root = mount((): NeonNode => element(<Carousel data={slides()} mode={mode} viewportFraction={0.8} defaultIndex={1}
		renderItem={(info: PageRenderItemInfo<string>): NeonNode => <Text>{info.item}</Text>} />));
	const outer = root.children[0];
	laidOut(outer, 300, 200);
	assert transformOf(outer.children[1]) === "translateX(30px) scale(1)", transformOf(outer.children[1]);
	assert transformOf(outer.children[0]) === "translateX(-210px) scale(0.8)", transformOf(outer.children[0]);
}
