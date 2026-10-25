import { domHost } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { ElementHandle } from "../../src/render/measure";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View, ScrollView, ScrollViewHandle } from "../../src/components/primitives";

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
function same(got: number[], x: float64, y: float64, width: float64, height: float64): boolean {
	return got.length === 4 && Math.abs(got[0] - x) < 0.01 && Math.abs(got[1] - y) < 0.01 && Math.abs(got[2] - width) < 0.01 && Math.abs(got[3] - height) < 0.01;
}
function inWindow(handle: ElementHandle): number[] {
	let got: number[] = [];
	handle.measureInWindow((x: number, y: number, width: number, height: number): void => { got = [x, y, width, height]; });
	return got;
}
function layoutIn(handle: ElementHandle, ancestor: ElementHandle): number[] {
	let got: number[] = [];
	handle.measureLayout(ancestor, (left: number, top: number, width: number, height: number): void => { got = [left, top, width, height]; }, (): void => { got = [-1]; });
	return got;
}

test "window measurement follows transforms while ancestor layout does not" {
	const handles: ElementHandle[] = [];
	const dispose = render(element(<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 80, top: 60, width: 200, height: 180, transform: "translateX(30px)" }}>
		<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 12, top: 80, width: 40, height: 20 }} />
	</View>), domHost(), mountPoint("measure-transform"));
	const anchor = handles[0];
	const parent = handles[1];
	assert same(inWindow(anchor), 122, 140, 40, 20);
	assert same(layoutIn(anchor, parent), 12, 80, 40, 20);
	js("document.querySelector('#measure-transform > div').style.transform = 'scale(2)'");
	assert same(inWindow(anchor), 4, 130, 80, 40);
	assert same(layoutIn(anchor, parent), 12, 80, 40, 20);
	let measured = "";
	anchor.measure((x: number, y: number, width: number, height: number, pageX: number, pageY: number): void => {
		measured = `${x},${y},${width},${height},${pageX},${pageY}`;
	});
	assert measured === "12,80,80,40,4,130", "measure: the layout origin in the parent, the transformed frame in the window: " + measured;
	const r = anchor.getBoundingClientRect();
	assert r.left === 4 && r.top === 130 && r.right === 84 && r.bottom === 170, `getBoundingClientRect ${r.left},${r.top},${r.right},${r.bottom}`;
	dispose();
}

test "layout crosses static wrappers and borders without subtracting painted rectangles" {
	const handles: ElementHandle[] = [];
	const dispose = render(element(<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 40, top: 30, width: 200, height: 160, borderWidth: 5, transform: "rotate(30deg)" }}>
		<View class="measure-static"><View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 12, top: 20, width: 30, height: 25 }} /></View>
	</View>), domHost(), mountPoint("measure-border"));
	js("document.querySelector('.measure-static').style.position = 'static'");
	assert same(layoutIn(handles[0], handles[1]), 17, 25, 30, 25);
	assert same(layoutIn(handles[1], handles[1]), 0, 0, 200, 160);
	dispose();
}

test "scroll changes window measurement but not layout measurement" {
	const anchors: ElementHandle[] = [];
	const scrolls: ScrollViewHandle[] = [];
	const dispose = render(element(<ScrollView style={{ position: "absolute", left: 20, top: 30, width: 120, height: 100 }} ref={(h: ScrollViewHandle): void => { scrolls.push(h); }}>
		<View style={{ height: 400 }}><View ref={(h: ElementHandle): void => { anchors.push(h); }} style={{ position: "absolute", left: 12, top: 80, width: 40, height: 20 }} /></View>
	</ScrollView>), domHost(), mountPoint("measure-scroll"));
	const before = inWindow(anchors[0]);
	assert same(layoutIn(anchors[0], scrolls[0]), 12, 80, 40, 20);
	scrolls[0].scrollTo({ y: 50, animated: false });
	const after = inWindow(anchors[0]);
	assert before[1] - after[1] === 50;
	assert same(layoutIn(anchors[0], scrolls[0]), 12, 80, 40, 20);
	dispose();
}

test "window bounds retain fractions and layout metrics expose CSSOM rounding" {
	const handles: ElementHandle[] = [];
	const dispose = render(element(<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 20, top: 30, width: 100, height: 100 }}>
		<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 12.25, top: 20.5, width: 30.25, height: 10.5 }} />
	</View>), domHost(), mountPoint("measure-fraction"));
	assert same(inWindow(handles[0]), 32.25, 50.5, 30.25, 10.5);
	assert same(layoutIn(handles[0], handles[1]), 12, 21, 30, 11);
	dispose();
}

test "a box not laid out and a removed node answer zeros, an unrelated node calls onFail, and a zero-size box is measured" {
	const handles: ElementHandle[] = [];
	const dispose = render(element(<View>
		<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 7, top: 9, width: 0, height: 0 }} />
		<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ display: "none", width: 20, height: 20 }} />
	</View>), domHost(), mountPoint("measure-failures"));
	const zero = inWindow(handles[0]);
	assert zero.length === 4 && zero[2] === 0 && zero[3] === 0 && (zero[0] !== 0 || zero[1] !== 0), "a zero-size box keeps its origin: " + zero.join(",");
	assert same(inWindow(handles[1]), 0, 0, 0, 0);
	assert layoutIn(handles[0], handles[1]).join(",") === "-1";
	js("document.querySelector('#measure-failures').remove()");
	assert same(inWindow(handles[0]), 0, 0, 0, 0);
	dispose();
}
