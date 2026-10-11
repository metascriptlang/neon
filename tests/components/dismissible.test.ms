import { createRoot } from "../../src/core/owner";
import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render, fireEventWith, fireTouch } from "../../src/render/host";
import { View, Text } from "../../src/components/primitives";
import { Dismissible, DismissDirection } from "../../src/components/dismissible";

function mount(app: () => NeonNode): MockNode {
	const root = mockNode("root");
	createRoot((): void => { render(app(), mockHost(), root as unknown as HostNode); });
	return root;
}

function laidOut(outer: MockNode, width: number, height: number): void {
	const e = neonEvent("layout");
	e.width = width;
	e.height = height;
	fireEventWith(outer, "onLayout", e);
}

function content(outer: MockNode): MockNode {
	return outer.children[outer.children.length - 1];
}

function transformOf(n: MockNode): string {
	const s = n.style;
	if (s === null) { return "none"; }
	return s.transform ?? "none";
}

function drag(target: MockNode, points: number[], step: number): void {
	let t = 1000.0;
	fireTouch(target, "onTouchStart", points[0], 10, t);
	for (let i = 1; i < points.length; i += 1) {
		t += step;
		fireTouch(target, "onTouchMove", points[i], 10, t);
	}
	t += step;
	fireTouch(target, "onTouchEnd", points[points.length - 1], 10, t);
}

function row(log: string[], direction: DismissDirection, confirm: boolean): NeonNode {
	return element(<Dismissible direction={direction} movementDuration={0} resizeDuration={0}
		confirmDismiss={(d: DismissDirection): boolean => { log.push("confirm " + d); return confirm; }}
		onDismissed={(d: DismissDirection): void => { log.push("dismissed " + d); }}
		background={<View><Text>archive</Text></View>}
		secondaryBackground={<View><Text>delete</Text></View>}>
		<View style={{ height: 60 }}><Text>mail</Text></View>
	</Dismissible>);
}

test "a slow drag past 40% dismisses towards its direction and collapses the row" {
	const log: string[] = [];
	const root = mount((): NeonNode => row(log, "horizontal", true));
	const outer = root.children[0];
	laidOut(outer, 300, 60);
	drag(content(outer).children[0], [10, 30, 80, 140, 200, 220], 100);
	assert log.join(",") === "confirm startToEnd,dismissed startToEnd", "dismissed: " + log.join(",");
	const style = outer.style;
	assert style !== null && style.height === 0, "the row collapsed to 0";
}

test "a slow drag under the threshold springs back" {
	const log: string[] = [];
	const root = mount((): NeonNode => row(log, "horizontal", true));
	const outer = root.children[0];
	laidOut(outer, 300, 60);
	drag(content(outer), [10, 30, 60, 80], 100);
	assert log.length === 0, "not dismissed: " + log.join(",");
	assert transformOf(content(outer)) === "translateX(0px)", "back at 0: " + transformOf(content(outer));
}

test "a fast fling dismisses below the threshold" {
	const log: string[] = [];
	const root = mount((): NeonNode => row(log, "horizontal", true));
	const outer = root.children[0];
	laidOut(outer, 300, 60);
	drag(content(outer), [100, 85, 70, 40], 10);
	assert log.join(",") === "confirm endToStart,dismissed endToStart", "a 3 px/ms fling left dismisses: " + log.join(",");
}

test "endToStart refuses a rightward drag and shows the secondary background on a leftward one" {
	const log: string[] = [];
	const root = mount((): NeonNode => row(log, "endToStart", false));
	const outer = root.children[0];
	laidOut(outer, 300, 60);
	const target = content(outer);
	fireTouch(target, "onTouchStart", 100, 10, 1);
	fireTouch(target, "onTouchMove", 150, 10, 100);
	assert transformOf(target) === "translateX(0px)" || transformOf(target) === "none", "a rightward drag does not move: " + transformOf(target);
	fireTouch(target, "onTouchEnd", 150, 10, 200);
	fireTouch(target, "onTouchStart", 200, 10, 300);
	fireTouch(target, "onTouchMove", 170, 10, 400);
	fireTouch(target, "onTouchMove", 100, 10, 500);
	const primary = outer.children[0].style;
	const secondary = outer.children[1].style;
	assert transformOf(target) === "translateX(-70px)", "dragged left: " + transformOf(target);
	assert primary !== null && primary.display === "none", "the primary background hides";
	assert secondary !== null && secondary.display === "flex", "the secondary background shows";
	fireTouch(target, "onTouchEnd", 0, 10, 600);
}

test "confirmDismiss false moves the row back and does not dismiss" {
	const log: string[] = [];
	const root = mount((): NeonNode => row(log, "horizontal", false));
	const outer = root.children[0];
	laidOut(outer, 300, 60);
	drag(content(outer), [10, 60, 120, 200], 100);
	assert log.join(",") === "confirm startToEnd", "asked once, not dismissed: " + log.join(",");
	assert transformOf(content(outer)) === "translateX(0px)", "back at 0: " + transformOf(content(outer));
}
