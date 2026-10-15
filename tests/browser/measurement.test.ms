import { domHost } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { ElementHandle, MeasureRect, MeasureError } from "../../src/render/measure";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View, ScrollView, ScrollViewHandle } from "../../src/components/primitives";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";

extern class HTMLElement {
	extern appendChild(child: HTMLElement): void;
	extern setAttribute(name: cstring, value: cstring): void;
}
extern class document {
	static body: HTMLElement;
	static extern createElement(tag: cstring): HTMLElement;
}
extern class window { static extern eval(code: cstring): string; }
function js(code: string): string { return window.eval(`String((() => { ${code} })())`); }
function mountPoint(id: string): HostNode {
	const node = document.createElement("div");
	node.setAttribute("id", id);
	document.body.appendChild(node);
	return node as unknown as HostNode;
}
function same(rect: MeasureRect, x: float64, y: float64, width: float64, height: float64): boolean {
	return Math.abs(rect.x - x) < 0.01 && Math.abs(rect.y - y) < 0.01 && Math.abs(rect.width - width) < 0.01 && Math.abs(rect.height - height) < 0.01;
}

test "window measurement follows transforms while ancestor layout does not" {
	const frames = useManualFrames();
	const handles: ElementHandle[] = [];
	const dispose = render(element(<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 80, top: 60, width: 200, height: 180, transform: "translateX(30px)" }}>
		<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 12, top: 80, width: 40, height: 20 }} />
	</View>), domHost(), mountPoint("measure-transform"));
	const anchor = handles[0];
	const parent = handles[1];
	const windowRects: MeasureRect[] = [];
	const layoutRects: MeasureRect[] = [];
	anchor.measureInWindow((r: MeasureRect): void => { windowRects.push(r); });
	anchor.measureLayout(parent, (r: MeasureRect): void => { layoutRects.push(r); });
	frames.step(1);
	assert windowRects.length === 1 && same(windowRects[0], 122, 140, 40, 20);
	assert layoutRects.length === 1 && same(layoutRects[0], 12, 80, 40, 20);
	js("document.querySelector('#measure-transform > div').style.transform = 'scale(2)'");
	anchor.measureInWindow((r: MeasureRect): void => { windowRects.push(r); });
	anchor.measureLayout(parent, (r: MeasureRect): void => { layoutRects.push(r); });
	frames.step(1);
	assert same(windowRects[1], 4, 130, 80, 40);
	assert same(layoutRects[1], 12, 80, 40, 20);
	dispose();
	setFrameDriver(null);
}

test "layout crosses static wrappers and borders without subtracting painted rectangles" {
	const frames = useManualFrames();
	const handles: ElementHandle[] = [];
	const dispose = render(element(<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 40, top: 30, width: 200, height: 160, borderWidth: 5, transform: "rotate(30deg)" }}>
		<View class="measure-static"><View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 12, top: 20, width: 30, height: 25 }} /></View>
	</View>), domHost(), mountPoint("measure-border"));
	js("document.querySelector('.measure-static').style.position = 'static'");
	let calls: int32 = 0;
	handles[0].measureLayout(handles[1], (r: MeasureRect): void => { assert same(r, 17, 25, 30, 25); calls += 1; });
	handles[1].measureLayout(handles[1], (r: MeasureRect): void => { assert same(r, 0, 0, 200, 160); calls += 1; });
	frames.step(1);
	assert calls === 2;
	dispose();
	setFrameDriver(null);
}

test "scroll changes window measurement but not layout measurement" {
	const frames = useManualFrames();
	const anchors: ElementHandle[] = [];
	const scrolls: ScrollViewHandle[] = [];
	const dispose = render(element(<ScrollView style={{ position: "absolute", left: 20, top: 30, width: 120, height: 100 }} ref={(h: ScrollViewHandle): void => { scrolls.push(h); }}>
		<View style={{ height: 400 }}><View ref={(h: ElementHandle): void => { anchors.push(h); }} style={{ position: "absolute", left: 12, top: 80, width: 40, height: 20 }} /></View>
	</ScrollView>), domHost(), mountPoint("measure-scroll"));
	const before: MeasureRect[] = [];
	const after: MeasureRect[] = [];
	anchors[0].measureInWindow((r: MeasureRect): void => { before.push(r); });
	anchors[0].measureLayout(scrolls[0], (r: MeasureRect): void => { before.push(r); });
	frames.step(1);
	scrolls[0].scrollTo({ y: 50, animated: false });
	anchors[0].measureInWindow((r: MeasureRect): void => { after.push(r); });
	anchors[0].measureLayout(scrolls[0], (r: MeasureRect): void => { after.push(r); });
	frames.step(1);
	assert before[0].y - after[0].y === 50;
	assert same(before[1], 12, 80, 40, 20) && same(after[1], 12, 80, 40, 20);
	dispose();
	setFrameDriver(null);
}

test "window bounds retain fractions and layout metrics expose CSSOM rounding" {
	const frames = useManualFrames();
	const handles: ElementHandle[] = [];
	const dispose = render(element(<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 20, top: 30, width: 100, height: 100 }}>
		<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 12.25, top: 20.5, width: 30.25, height: 10.5 }} />
	</View>), domHost(), mountPoint("measure-fraction"));
	let calls: int32 = 0;
	handles[0].measureInWindow((r: MeasureRect): void => { assert same(r, 32.25, 50.5, 30.25, 10.5); calls += 1; });
	handles[0].measureLayout(handles[1], (r: MeasureRect): void => { assert same(r, 12, 21, 30, 11); calls += 1; });
	frames.step(1);
	assert calls === 2;
	dispose();
	setFrameDriver(null);
}

test "missing boxes and invalid ancestry fail while zero-size boxes remain measurable" {
	const frames = useManualFrames();
	const handles: ElementHandle[] = [];
	const dispose = render(element(<View>
		<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ width: 0, height: 0 }} />
		<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ display: "none", width: 20, height: 20 }} />
	</View>), domHost(), mountPoint("measure-failures"));
	let calls: int32 = 0;
	handles[0].measureInWindow((r: MeasureRect): void => { assert r.width === 0 && r.height === 0; calls += 1; });
	handles[1].measureInWindow((r: MeasureRect): void => { assert false; }, (error: MeasureError): void => { assert error === MeasureError.NotLaidOut; calls += 1; });
	handles[0].measureLayout(handles[1], (r: MeasureRect): void => { assert false; }, (error: MeasureError): void => { calls += 1; });
	frames.step(1);
	assert calls === 3;
	js("document.querySelector('#measure-failures').remove()");
	handles[0].measureInWindow((r: MeasureRect): void => { assert false; }, (error: MeasureError): void => { assert error === MeasureError.NotMounted; calls += 1; });
	frames.step(1);
	assert calls === 4;
	dispose();
	setFrameDriver(null);
}
