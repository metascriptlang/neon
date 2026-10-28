import { View, Text, Pressable, ScrollView, ScrollViewHandle } from "../../src/components/primitives";
import { ElementHandle } from "../../src/render/measure";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";

function near(a: float64, b: float64): boolean { return Math.abs(a - b) < 0.05; }

export function MeasurementApp(): NeonNode {
	const [status, setStatus] = createSignal("measurement ready");
	const handles: ElementHandle[] = [];
	const anchors: ElementHandle[] = [];
	const scrolls: ScrollViewHandle[] = [];
	const measure = (event: NeonEvent): void => {
		setStatus("measurement running");
		let parent: number[] = [];
		let frame: number[] = [];
		let layout: number[] = [];
		let before = 0.0;
		let after = 0.0;
		let local: number[] = [];
		const ancestorFailed = (): void => { setStatus("measurement FAIL an ancestor measureLayout called onFail"); };
		handles[1].measureInWindow((x: number, y: number, width: number, height: number): void => { parent = [x, y]; });
		handles[0].measureInWindow((x: number, y: number, width: number, height: number): void => { frame = [x, y, width, height]; });
		handles[0].measureLayout(handles[1], (left: number, top: number, width: number, height: number): void => { layout = [left, top, width, height]; }, ancestorFailed);
		if (layout.length === 0) { return; }
		if (!near(frame[0] - parent[0], 24) || !near(frame[1] - parent[1], 160) || !near(frame[2], 80) || !near(frame[3], 40) || !near(layout[0], 12) || !near(layout[1], 80) || !near(layout[2], 40) || !near(layout[3], 20)) {
			setStatus(`measurement FAIL geometry ${frame[0] - parent[0]},${frame[1] - parent[1]},${frame[2]},${frame[3]} local ${layout[0]},${layout[1]},${layout[2]},${layout[3]}`);
			return;
		}
		anchors[0].measureInWindow((x: number, y: number, width: number, height: number): void => { before = y; });
		scrolls[0].scrollTo({ y: 50, animated: false });
		anchors[0].measureInWindow((x: number, y: number, width: number, height: number): void => { after = y; });
		anchors[0].measureLayout(scrolls[0], (left: number, top: number, width: number, height: number): void => { local = [left, top]; }, ancestorFailed);
		if (local.length === 0) { return; }
		if (!near(before - after, 50) || !near(local[0], 12) || !near(local[1], 80)) {
			setStatus(`measurement FAIL scroll ${before - after} local ${local[0]},${local[1]}`);
			return;
		}
		setStatus(`measurement PASS ${frame[0]},${frame[1]},${frame[2]},${frame[3]}`);
	};
	return <View style={{ flex: 1 }}>
		<Pressable accessibilityLabel="Run measurement" style={{ position: "absolute", left: 20, top: 20, width: 180, height: 44 }} onPress={measure}><Text>Run measurement</Text></Pressable>
		<Text>{status()}</Text>
		<View ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 80, top: 160, width: 200, height: 180, transform: "scale(2)", backgroundColor: "#dddddd" }}>
			<View accessible={true} accessibilityLabel="measurement-anchor" ref={(h: ElementHandle): void => { handles.push(h); }} style={{ position: "absolute", left: 12, top: 80, width: 40, height: 20, backgroundColor: "#ff0000" }} />
		</View>
		<ScrollView ref={(h: ScrollViewHandle): void => { scrolls.push(h); }} style={{ position: "absolute", left: 20, top: 430, width: 180, height: 100 }}>
			<View style={{ height: 400 }}><View ref={(h: ElementHandle): void => { anchors.push(h); }} style={{ position: "absolute", left: 12, top: 80, width: 40, height: 20, backgroundColor: "#00aa00" }} /></View>
		</ScrollView>
	</View>;
}
