import { View, Text, Pressable, ScrollView, ScrollViewHandle } from "../../../src/components/primitives";
import { ElementHandle } from "../../../src/render/measure";
import { NeonNode } from "../../../src/render/hostTypes";
import { createSignal } from "../../../src/core/signal";
import { Show } from "../../../src/macros/ui/flow";
import { runApp } from "../../../src/platform/native/host";

function near(a: float64, b: float64): boolean { return Math.abs(a - b) < 0.05; }

function describe(x: number, y: number, width: number, height: number): string {
	return `${x},${y},${width},${height}`;
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
	const fail = (message: string): void => {
		failed = true;
		setStatus("geometry FAIL " + message);
	};
	const done = (): void => {
		completed += 1;
		if (completed === 7 && !failed) {
			geometryReady = true;
			setStatus("geometry PASS");
		}
	};
	const ancestorFailed = (): void => { fail("an ancestor measureLayout called onFail"); };
	const measure = (): void => {
		if (geometryReady || completed !== 0) { fail("run measurement only once"); return; }
		setStatus("geometry running");
		scaled[0].measureInWindow((x: number, y: number, width: number, height: number): void => {
			setScaledResult("scaled " + describe(x, y, width, height));
			done();
		});
		scaled[0].measureLayout(parents[0], (left: number, top: number, width: number, height: number): void => {
			if (!near(left, 40) || !near(top, 35) || !near(width, 40) || !near(height, 20)) {
				fail("scaled logical ancestor " + describe(left, top, width, height)); return;
			}
			setLocalResult("local " + describe(left, top, width, height));
			done();
		}, ancestorFailed);
		anchors[0].measureInWindow((x: number, y: number, width: number, height: number): void => {
			setScrollResult("scroll " + describe(x, y, width, height));
			done();
		});
		anchors[0].measureLayout(scrolls[0], (left: number, top: number, width: number, height: number): void => {
			if (!near(left, 12) || !near(top, 60) || !near(width, 40) || !near(height, 20)) {
				fail("initial scroll logical ancestor " + describe(left, top, width, height)); return;
			}
			done();
		}, ancestorFailed);
		zeros[0].measureInWindow((x: number, y: number, width: number, height: number): void => {
			if (!near(width, 0) || !near(height, 0)) { fail("zero " + describe(x, y, width, height)); return; }
			setZeroResult("zero PASS");
			done();
		});
		hidden[0].measureInWindow((x: number, y: number, width: number, height: number): void => {
			if (x !== 0 || y !== 0 || width !== 0 || height !== 0) { fail("hidden " + describe(x, y, width, height)); return; }
			done();
		});
		scaled[0].measureLayout(zeros[0], (left: number, top: number, width: number, height: number): void => { fail("nonancestor succeeded"); }, done);
	};
	const scroll = (): void => {
		if (!geometryReady || scrolled) { fail("scroll requires fresh geometry PASS"); return; }
		scrolled = true;
		setStatus("geometry scrolling");
		scrolls[0].scrollTo({ y: 40, animated: false });
		anchors[0].measureInWindow((x: number, y: number, width: number, height: number): void => {
			setScrollResult("scroll " + describe(x, y, width, height));
		});
		anchors[0].measureLayout(scrolls[0], (left: number, top: number, width: number, height: number): void => {
			if (!near(left, 12) || !near(top, 60) || !near(width, 40) || !near(height, 20)) {
				fail("scrolled logical ancestor " + describe(left, top, width, height)); return;
			}
			setLocalResult("local " + describe(left, top, width, height));
			setStatus("geometry SCROLLED");
		}, ancestorFailed);
	};
	const dispose = (): void => {
		if (!live()) { setLifetime("lifetime FAIL duplicate disposal"); return; }
		let answers: int32 = 0;
		temporary[0].measureInWindow((x: number, y: number, width: number, height: number): void => { if (near(width, 40)) { answers += 1; } });
		temporary[0].measureLayout(roots[0], (left: number, top: number, width: number, height: number): void => { answers += 1; });
		setLive(false);
		setLifetime(answers === 2 ? "lifetime disposed after 2 answers" : "lifetime FAIL a mounted View did not answer before the call returned");
	};
	const checkDisposed = (): void => {
		if (live()) { setLifetime("lifetime FAIL disposal precondition"); return; }
		let inWindow = "";
		let layout = "";
		temporary[0].measureInWindow((x: number, y: number, width: number, height: number): void => { inWindow = describe(x, y, width, height); });
		temporary[0].measureLayout(roots[0], (left: number, top: number, width: number, height: number): void => { layout = "measured"; }, (): void => { layout = "onFail"; });
		if (inWindow !== "0,0,0,0" || layout !== "onFail") { setLifetime(`lifetime FAIL after unmount window ${inWindow} layout ${layout}`); return; }
		setLifetime("lifetime PASS window-zeros layout-onFail");
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
