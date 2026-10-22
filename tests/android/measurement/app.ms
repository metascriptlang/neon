import { View, Text, Pressable, ScrollView, ScrollViewHandle } from "../../../src/components/primitives";
import { ElementHandle, MeasureRect, MeasureError } from "../../../src/render/measure";
import { NeonNode } from "../../../src/render/hostTypes";
import { createSignal } from "../../../src/core/signal";
import { Show } from "../../../src/macros/ui/flow";
import { requestFrame } from "../../../src/animation/frame";
import { runApp } from "../../../src/platform/native/host";

function near(a: float64, b: float64): boolean { return Math.abs(a - b) < 0.05; }

function describe(rect: MeasureRect): string {
	return `${rect.x},${rect.y},${rect.width},${rect.height}`;
}

function MeasurementApp(): NeonNode {
	const [status, setStatus] = createSignal("geometry ready");
	const [scaledResult, setScaledResult] = createSignal("scaled ready");
	const [scrollResult, setScrollResult] = createSignal("scroll ready");
	const [localResult, setLocalResult] = createSignal("local ready");
	const [zeroResult, setZeroResult] = createSignal("zero ready");
	const [lifetime, setLifetime] = createSignal("lifetime ready");
	const [live, setLive] = createSignal(true);
	const roots: ElementHandle[] = [];
	const parents: ElementHandle[] = [];
	const scaled: ElementHandle[] = [];
	const scrolls: ScrollViewHandle[] = [];
	const anchors: ElementHandle[] = [];
	const zeros: ElementHandle[] = [];
	const hidden: ElementHandle[] = [];
	const temporary: ElementHandle[] = [];
	let completed: int32 = 0;
	let failed = false;
	let geometryReady = false;
	let scrolled = false;
	let queuedCallbacks: int32 = 0;
	const fail = (message: string): void => {
		failed = true;
		setStatus("geometry FAIL " + message);
	};
	const measurementFailed = (error: MeasureError): void => { fail(error.toString()); };
	const done = (): void => {
		completed += 1;
		if (completed === 7 && !failed) {
			geometryReady = true;
			setStatus("geometry PASS");
		}
	};
	const measure = (): void => {
		if (geometryReady || completed !== 0) { fail("run measurement only once"); return; }
		setStatus("geometry running");
		scaled[0].measureInWindow((rect: MeasureRect): void => {
			setScaledResult("scaled " + describe(rect));
			done();
		}, measurementFailed);
		scaled[0].measureLayout(parents[0], (rect: MeasureRect): void => {
			if (!near(rect.x, 40) || !near(rect.y, 35) || !near(rect.width, 40) || !near(rect.height, 20)) {
				fail("scaled logical ancestor " + describe(rect)); return;
			}
			setLocalResult("local " + describe(rect));
			done();
		}, measurementFailed);
		anchors[0].measureInWindow((rect: MeasureRect): void => {
			setScrollResult("scroll " + describe(rect));
			done();
		}, measurementFailed);
		anchors[0].measureLayout(scrolls[0], (rect: MeasureRect): void => {
			if (!near(rect.x, 12) || !near(rect.y, 60) || !near(rect.width, 40) || !near(rect.height, 20)) {
				fail("initial scroll logical ancestor " + describe(rect)); return;
			}
			done();
		}, measurementFailed);
		zeros[0].measureInWindow((rect: MeasureRect): void => {
			if (!near(rect.width, 0) || !near(rect.height, 0)) { fail("zero " + describe(rect)); return; }
			setZeroResult("zero PASS");
			done();
		}, measurementFailed);
		hidden[0].measureInWindow((rect: MeasureRect): void => { fail("hidden succeeded"); }, (error: MeasureError): void => {
			if (error !== MeasureError.NotLaidOut) { fail("hidden " + error.toString()); return; }
			done();
		});
		scaled[0].measureLayout(zeros[0], (rect: MeasureRect): void => { fail("nonancestor succeeded"); }, (error: MeasureError): void => {
			if (error !== MeasureError.NotAncestor) { fail("nonancestor " + error.toString()); return; }
			done();
		});
	};
	const scroll = (): void => {
		if (!geometryReady || scrolled) { fail("scroll requires fresh geometry PASS"); return; }
		scrolled = true;
		setStatus("geometry scrolling");
		scrolls[0].scrollTo({ y: 40, animated: false });
		anchors[0].measureInWindow((rect: MeasureRect): void => {
			setScrollResult("scroll " + describe(rect));
			anchors[0].measureLayout(scrolls[0], (local: MeasureRect): void => {
				if (!near(local.x, 12) || !near(local.y, 60) || !near(local.width, 40) || !near(local.height, 20)) {
					fail("scrolled logical ancestor " + describe(local)); return;
				}
				setLocalResult("local " + describe(local));
				setStatus("geometry SCROLLED");
			}, measurementFailed);
		}, measurementFailed);
	};
	const dispose = (): void => {
		if (!live()) { setLifetime("lifetime FAIL duplicate disposal"); return; }
		const called = (rect: MeasureRect): void => {
			queuedCallbacks += 1;
			setLifetime("lifetime FAIL queued success delivered");
		};
		const rejected = (error: MeasureError): void => {
			queuedCallbacks += 1;
			setLifetime("lifetime FAIL queued failure delivered");
		};
		temporary[0].measureInWindow(called, rejected);
		temporary[0].measureLayout(roots[0], called, rejected);
		setLive(false);
		requestFrame((time: number): void => {
			if (queuedCallbacks === 0) { setLifetime("lifetime queued 0"); }
		});
	};
	const checkDisposed = (): void => {
		if (live() || queuedCallbacks !== 0) { setLifetime("lifetime FAIL disposal precondition"); return; }
		let windowRejected = false;
		let layoutRejected = false;
		try {
			temporary[0].measureInWindow((rect: MeasureRect): void => { queuedCallbacks += 1; });
		} catch (error) { windowRejected = error.toString().indexOf("was called after unmount") >= 0; }
		try {
			temporary[0].measureLayout(roots[0], (rect: MeasureRect): void => { queuedCallbacks += 1; });
		} catch (error) { layoutRejected = error.toString().indexOf("was called after unmount") >= 0; }
		if (!windowRejected || !layoutRejected) { setLifetime("lifetime FAIL stale call accepted or wrong error"); return; }
		requestFrame((time: number): void => {
			if (queuedCallbacks === 0) { setLifetime("lifetime PASS 0 window-rejected layout-rejected"); }
			else { setLifetime("lifetime FAIL stale callback delivered"); }
		});
	};
	return <View accessible={true} accessibilityLabel="measurement-root" ref={(handle: ElementHandle): void => { roots.push(handle); }} style={{ flex: 1 }}>
		<Pressable accessibilityLabel="Run measurement" onPress={measure} style={{ position: "absolute", left: 12, top: 12, width: 190, height: 44 }}><Text>Run measurement</Text></Pressable>
		<Pressable accessibilityLabel="Scroll measurement" onPress={scroll} style={{ position: "absolute", left: 12, top: 62, width: 190, height: 44 }}><Text>Scroll measurement</Text></Pressable>
		<Pressable accessibilityLabel="Dispose measurement" onPress={dispose} style={{ position: "absolute", left: 12, top: 112, width: 168, height: 44 }}><Text>Dispose measurement</Text></Pressable>
		<Pressable accessibilityLabel="Check disposed" onPress={checkDisposed} style={{ position: "absolute", left: 184, top: 112, width: 140, height: 44 }}><Text>Check disposed</Text></Pressable>
		<View ref={(handle: ElementHandle): void => { parents.push(handle); }} style={{ position: "absolute", left: 60, top: 210, width: 140, height: 100, transform: "scale(1.5) rotate(90deg)", backgroundColor: "#dddddd" }}>
			<View accessible={true} accessibilityLabel="measurement-scaled" ref={(handle: ElementHandle): void => { scaled.push(handle); }} style={{ position: "absolute", left: 40, top: 35, width: 40, height: 20, backgroundColor: "#ff0000" }} />
		</View>
		<View ref={(handle: ElementHandle): void => { zeros.push(handle); }} style={{ position: "absolute", left: 280, top: 340, width: 0, height: 0 }} />
		<View ref={(handle: ElementHandle): void => { hidden.push(handle); }} style={{ display: "none", width: 10, height: 10 }} />
		<ScrollView ref={(handle: ScrollViewHandle): void => { scrolls.push(handle); }} style={{ position: "absolute", left: 20, top: 380, width: 180, height: 100 }}>
			<View style={{ height: 400 }}><View accessible={true} accessibilityLabel="measurement-scroll" ref={(handle: ElementHandle): void => { anchors.push(handle); }} style={{ position: "absolute", left: 12, top: 60, width: 40, height: 20, backgroundColor: "#00aa00" }} /></View>
		</ScrollView>
		<Show when={live()}><View accessible={true} accessibilityLabel="measurement-temporary" ref={(handle: ElementHandle): void => { temporary.push(handle); }} style={{ position: "absolute", left: 240, top: 400, width: 40, height: 20, backgroundColor: "#0000ff" }} /></Show>
		<Text style={{ position: "absolute", left: 12, top: 500, width: 310, height: 24 }}>{status()}</Text>
		<Text style={{ position: "absolute", left: 12, top: 528, width: 310, height: 24 }}>{scaledResult()}</Text>
		<Text style={{ position: "absolute", left: 12, top: 556, width: 310, height: 24 }}>{scrollResult()}</Text>
		<Text style={{ position: "absolute", left: 12, top: 584, width: 310, height: 24 }}>{localResult()}</Text>
		<Text style={{ position: "absolute", left: 12, top: 612, width: 310, height: 24 }}>{zeroResult()}</Text>
		<Text style={{ position: "absolute", left: 12, top: 640, width: 310, height: 48 }}>{lifetime()}</Text>
	</View>;
}

runApp(MeasurementApp);
