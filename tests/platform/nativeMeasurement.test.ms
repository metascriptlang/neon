import { runApp } from "../../src/platform/native/host";
import { View, ScrollView, ScrollViewHandle } from "../../src/components/primitives";
import { ElementHandle } from "../../src/render/measure";
import { NeonNode } from "../../src/render/hostTypes";
import { nmTeardown, nmScroll, nmLastScrollTag, nmMeasurementRect } from "./nativeBridgeMock.h";

test "native ancestor measurement reads Yoga layout rather than transformed window bounds" {
	const handles: ElementHandle[] = [];
	runApp((): NeonNode => <View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 80, top: 60, width: 200, height: 180, transform: "scale(2)" }}>
		<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 12, top: 80, width: 40, height: 20 }} />
	</View>);
	nmMeasurementRect(4, 130, 80, 40, 1);
	let got = "";
	handles[0].measureLayout(handles[1], (left: number, top: number, width: number, height: number): void => { got += `layout ${left},${top},${width},${height};`; });
	handles[0].measureInWindow((x: number, y: number, width: number, height: number): void => { got += `window ${x},${y},${width},${height};`; });
	handles[0].measure((x: number, y: number, width: number, height: number, pageX: number, pageY: number): void => {
		got += `measure ${x},${y},${width},${height},${pageX},${pageY};`;
	});
	handles[1].measureLayout(handles[1], (left: number, top: number, width: number, height: number): void => { got += `self ${left},${top},${width},${height}`; });
	assert got === "layout 12,80,40,20;window 4,130,80,40;measure 12,80,80,40,4,130;self 0,0,200,180", got;
	nmTeardown();
}

test "native scrolling does not change ancestor layout coordinates" {
	const anchors: ElementHandle[] = [];
	const scrolls: ScrollViewHandle[] = [];
	runApp((): NeonNode => <ScrollView ref={(h: ScrollViewHandle): void => { scrolls.push(h); }} style={{ height: 100 }}>
		<View style={{ height: 400 }}><View ref={(h: ElementHandle): void => { anchors.push(h); }} style={{ position: "absolute", left: 12, top: 80, width: 40, height: 20 }} /></View>
	</ScrollView>);
	nmScroll(nmLastScrollTag(), 0, 50, 400, 100, 400, 400);
	let got = "";
	anchors[0].measureLayout(scrolls[0], (left: number, top: number, width: number, height: number): void => { got = `${left},${top}`; });
	assert got === "12,80", got;
	nmTeardown();
}

test "native measurement answers zeros for a view not laid out and calls onFail for an unrelated node" {
	const handles: ElementHandle[] = [];
	runApp((): NeonNode => <View>
		<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ width: 0, height: 0 }} />
		<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ width: 10, height: 10 }} />
	</View>);
	let got = "";
	const answer = (x: number, y: number, width: number, height: number): void => { got += `${x},${y},${width},${height};`; };
	nmMeasurementRect(0, 0, 0, 0, 1);
	handles[0].measureInWindow(answer);
	handles[0].measureLayout(handles[1], (left: number, top: number, width: number, height: number): void => { got += "measured;"; }, (): void => { got += "onFail;"; });
	nmMeasurementRect(5, 5, 5, 5, 0);
	handles[0].measureInWindow(answer);
	nmTeardown();
	handles[0].measureInWindow(answer);
	assert got === "0,0,0,0;onFail;0,0,0,0;0,0,0,0;", got;
}
