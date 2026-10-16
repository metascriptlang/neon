import { View, Text, Pressable, ScrollView, ScrollViewHandle } from "../../src/components/primitives";
import { ElementHandle, MeasureRect, MeasureError } from "../../src/render/measure";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";

function near(a: float64, b: float64): boolean { return Math.abs(a - b) < 0.05; }

export function MeasurementApp(): NeonNode {
	const [status, setStatus] = createSignal("measurement ready");
	const handles: ElementHandle[] = [];
	const anchors: ElementHandle[] = [];
	const scrolls: ScrollViewHandle[] = [];
	const fail = (error: MeasureError): void => { setStatus("measurement FAIL: " + error.toString()); };
	const measure = (event: NeonEvent): void => {
		setStatus("measurement running");
		handles[1].measureInWindow((parent: MeasureRect): void => {
			handles[0].measureInWindow((window: MeasureRect): void => {
				handles[0].measureLayout(handles[1], (layout: MeasureRect): void => {
					if (!near(window.x - parent.x, 24) || !near(window.y - parent.y, 160) || !near(window.width, 80) || !near(window.height, 40) || !near(layout.x, 12) || !near(layout.y, 80) || !near(layout.width, 40) || !near(layout.height, 20)) {
						setStatus(`measurement FAIL geometry ${window.x - parent.x},${window.y - parent.y},${window.width},${window.height} local ${layout.x},${layout.y},${layout.width},${layout.height}`);
						return;
					}
					anchors[0].measureInWindow((before: MeasureRect): void => {
						scrolls[0].scrollTo({ y: 50, animated: false });
						anchors[0].measureInWindow((after: MeasureRect): void => {
							anchors[0].measureLayout(scrolls[0], (local: MeasureRect): void => {
								if (!near(before.y - after.y, 50) || !near(local.x, 12) || !near(local.y, 80)) {
									setStatus(`measurement FAIL scroll ${before.y - after.y} local ${local.x},${local.y}`);
									return;
								}
								setStatus(`measurement PASS ${window.x},${window.y},${window.width},${window.height}`);
							}, fail);
						}, fail);
					}, fail);
				}, fail);
			}, fail);
		}, fail);
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
