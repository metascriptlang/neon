import { runApp } from "../../src/platform/native/host";
import { View, ScrollView, ScrollViewHandle } from "../../src/components/primitives";
import { ElementHandle, MeasureRect, MeasureError } from "../../src/render/measure";
import { NeonNode } from "../../src/render/hostTypes";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";
import { nmTeardown, nmScroll, nmLastScrollTag, nmMeasurementRect } from "./nativeBridgeMock.h";

test "native ancestor measurement reads Yoga layout rather than transformed window bounds" {
	const handles: ElementHandle[] = [];
	runApp((): NeonNode => <View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 80, top: 60, width: 200, height: 180, transform: "scale(2)" }}>
		<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 12, top: 80, width: 40, height: 20 }} />
	</View>);
	const frames = useManualFrames();
	nmMeasurementRect(4, 130, 80, 40, 1);
	let calls: int32 = 0;
	handles[0].measureLayout(handles[1], (r: MeasureRect): void => { assert r.x === 12 && r.y === 80 && r.width === 40 && r.height === 20; calls += 1; });
	handles[0].measureInWindow((r: MeasureRect): void => { assert r.x === 4 && r.y === 130 && r.width === 80 && r.height === 40; calls += 1; });
	handles[1].measureLayout(handles[1], (r: MeasureRect): void => { assert r.x === 0 && r.y === 0 && r.width === 200; calls += 1; });
	frames.step(1);
	assert calls === 3;
	nmTeardown();
	setFrameDriver(null);
}

test "native scrolling does not change ancestor layout coordinates" {
	const anchors: ElementHandle[] = [];
	const scrolls: ScrollViewHandle[] = [];
	runApp((): NeonNode => <ScrollView ref={(h: ScrollViewHandle): void => { scrolls.push(h); }} style={{ height: 100 }}>
		<View style={{ height: 400 }}><View ref={(h: ElementHandle): void => { anchors.push(h); }} style={{ position: "absolute", left: 12, top: 80, width: 40, height: 20 }} /></View>
	</ScrollView>);
	const frames = useManualFrames();
	nmScroll(nmLastScrollTag(), 0, 50, 400, 100, 400, 400);
	let calls: int32 = 0;
	anchors[0].measureLayout(scrolls[0], (r: MeasureRect): void => { assert r.x === 12 && r.y === 80; calls += 1; });
	frames.step(1);
	assert calls === 1;
	nmTeardown();
	setFrameDriver(null);
}

test "native measurement distinguishes not ready and unrelated nodes from valid zero bounds" {
	const handles: ElementHandle[] = [];
	runApp((): NeonNode => <View>
		<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ width: 0, height: 0 }} />
		<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ width: 10, height: 10 }} />
	</View>);
	const frames = useManualFrames();
	let calls: int32 = 0;
	nmMeasurementRect(0, 0, 0, 0, 1);
	handles[0].measureInWindow((r: MeasureRect): void => { assert r.width === 0 && r.height === 0; calls += 1; });
	handles[0].measureLayout(handles[1], (r: MeasureRect): void => { assert false; }, (e: MeasureError): void => { assert e === MeasureError.NotAncestor; calls += 1; });
	frames.step(1);
	nmMeasurementRect(0, 0, 0, 0, 0);
	handles[0].measureInWindow((r: MeasureRect): void => { assert false; }, (e: MeasureError): void => { assert e === MeasureError.NotLaidOut; calls += 1; });
	frames.step(1);
	assert calls === 3;
	handles[0].measureInWindow((r: MeasureRect): void => { assert false; });
	nmTeardown();
	frames.step(1);
	setFrameDriver(null);
}
