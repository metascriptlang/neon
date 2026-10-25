// The native geometry exports of the macOS bridge (niMeasureInWindow and niMeasurementX/Y/W/H): a view's bounds in the
// window's content, top-left origin, in points, with its painted transforms and its ancestors' scroll applied.
//   msc build examples/macosNative/ionMeasure.ms --output=out/macosIonMeasure
//   out/macosIonMeasure --check    measures each labelled view through the harness and exits 0 when every bound holds

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { ElementHandle, MeasureRect } from "../../src/render/measure";
import { View, ScrollView, ScrollViewHandle } from "../../src/components/primitives";
import { Show } from "../../src/macros/ui/flow";
import { createSignal } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import {
	harnessIsCheck,
	harnessMeasure,
	harnessMeasureDetached,
	harnessHide,
	harnessMeasureRoot,
} from "./harness.h";
import { exit } from "std/process";

when (macos) {
	@compile("./harness.m", "-fobjc-arc");
}

const styles = createStyles({
	base: { width: 480, height: 320, backgroundColor: "#101820" },
	plain: {
		position: "absolute", left: 20, top: 30, width: 100, height: 50,
		backgroundColor: "#2e86de",
	},
	scaled: {
		position: "absolute", left: 200, top: 20, width: 100, height: 100,
		backgroundColor: "#27ae60", transform: "scale(0.5)",
	},
	scaledChild: {
		position: "absolute", left: 0, top: 0, width: 50, height: 50,
		backgroundColor: "#e74c3c",
	},
	rotated: {
		position: "absolute", left: 20, top: 120, width: 80, height: 20,
		backgroundColor: "#9b59b6", transform: "rotate(90deg)",
	},
	scroll: {
		position: "absolute", left: 340, top: 20, width: 120, height: 200,
		backgroundColor: "#34495e",
	},
	content: { height: 600 },
	band: {
		position: "absolute", left: 10, top: 300, width: 50, height: 40,
		backgroundColor: "#f1c40f",
	},
	zero: { position: "absolute", left: 0, top: 0, width: 0, height: 0 },
	hidden: { display: "none", width: 20, height: 20 },
	disposable: { position: "absolute", left: 200, top: 200, width: 20, height: 20 },
});

let root: ElementHandle | null = null;
let plain: ElementHandle | null = null;
let scaled: ElementHandle | null = null;
let child: ElementHandle | null = null;
let rotated: ElementHandle | null = null;
let band: ElementHandle | null = null;
let zero: ElementHandle | null = null;
let hidden: ElementHandle | null = null;
let disposable: ElementHandle | null = null;
let scroll: ScrollViewHandle | null = null;
let disposed = false;
const [visible, setVisible] = createSignal(true);

function Disposable(): NeonNode {
	onCleanup((): void => { disposed = true; });
	return <View style={styles.disposable}
		ref={(h: ElementHandle): void => { disposable = h; }} />;
}

function App(): NeonNode {
	return <View style={styles.base} ref={(h: ElementHandle): void => { root = h; }}>
		<View style={styles.plain} accessibilityLabel="plain"
			ref={(h: ElementHandle): void => { plain = h; }} />
		<View style={styles.scaled} accessibilityLabel="scaled"
			ref={(h: ElementHandle): void => { scaled = h; }}>
			<View style={styles.scaledChild} accessibilityLabel="scaledChild"
				ref={(h: ElementHandle): void => { child = h; }} />
		</View>
		<View style={styles.rotated} accessibilityLabel="rotated"
			ref={(h: ElementHandle): void => { rotated = h; }} />
		<ScrollView style={styles.scroll}
			ref={(h: ScrollViewHandle): void => { scroll = h; }}>
			<View style={styles.content}>
				<View style={styles.band} accessibilityLabel="band"
					ref={(h: ElementHandle): void => { band = h; }} />
			</View>
		</ScrollView>
		<View style={styles.zero} ref={(h: ElementHandle): void => { zero = h; }} />
		<View style={styles.hidden} ref={(h: ElementHandle): void => { hidden = h; }} />
		<Show when={visible()}><Disposable /></Show>
	</View>;
}

const TITLE = "Neon measure on Ion";
let failures: int32 = 0;
let checks: int32 = 0;
let requested: int32 = 0;
let completed: int32 = 0;
let directChecks: int32 = 0;

function directBounds(label: string, want: string): void {
	const got: string = harnessMeasure(TITLE, label);
	directChecks += 1;
	expect("native export " + label, got === want, `${got}, want ${want}`);
}

function expect(name: string, ok: boolean, detail: string): void {
	checks += 1;
	console.log(`${ok ? "ok  " : "FAIL"} ${name}: ${detail}`);
	if (!ok) { failures += 1; }
}

function requireHandle(name: string, handle: ElementHandle | null): ElementHandle {
	if (handle === null) { throw "Missing public ref: " + name; }
	return handle as ElementHandle;
}

function near(a: float64, b: float64): boolean { return Math.abs(a - b) < 0.05; }

function rectText(rect: MeasureRect): string {
	return `${rect.x},${rect.y},${rect.width},${rect.height}`;
}

function bounds(
	name: string,
	handle: ElementHandle,
	want: MeasureRect,
	ancestor: ElementHandle | null = null,
): void {
	requested += 1;
	const success = (x: number, y: number, width: number, height: number): void => {
		completed += 1;
		expect(name, near(x, want.x) && near(y, want.y) && near(width, want.width) && near(height, want.height),
			`${x},${y},${width},${height}, want ${rectText(want)}`);
	};
	if (ancestor === null) { handle.measureInWindow(success); }
	else {
		handle.measureLayout(ancestor as ElementHandle, success, (): void => {
			completed += 1;
			expect(name, false, "onFail");
		});
	}
}

function layoutFails(name: string, handle: ElementHandle, ancestor: ElementHandle): void {
	requested += 1;
	handle.measureLayout(ancestor, (left: number, top: number, width: number, height: number): void => {
		completed += 1;
		expect(name, false, `unexpected bounds ${left},${top},${width},${height}`);
	}, (): void => {
		completed += 1;
		expect(name, true, "onFail");
	});
}

function delivered(name: string): void {
	expect(name, completed === requested, `${completed}/${requested} callbacks`);
	if (failures !== 0) { exit(failures); }
}

function atStart(): void {
	const nativeRoot: string = harnessMeasureRoot(TITLE);
	directChecks += 1;
	expect("native export root", nativeRoot === "0,0,480,320", nativeRoot);
	directBounds("plain", "20,30,100,50");
	directBounds("scaled", "225,45,50,50");
	directBounds("scaledChild", "225,45,25,25");
	directBounds("rotated", "50,90,20,80");
	directBounds("band", "350,320,50,40");
	const base = requireHandle("root", root);
	bounds("root window points", base, { x: 0, y: 0, width: 480, height: 320 });
	bounds("ordinary window points", requireHandle("plain", plain),
		{ x: 20, y: 30, width: 100, height: 50 });
	bounds("scaled parent AABB", requireHandle("scaled", scaled),
		{ x: 225, y: 45, width: 50, height: 50 });
	bounds("scaled child AABB", requireHandle("child", child),
		{ x: 225, y: 45, width: 25, height: 25 });
	bounds("child logical parent layout", requireHandle("child", child),
		{ x: 0, y: 0, width: 50, height: 50 }, requireHandle("scaled", scaled));
	bounds("child logical root layout", requireHandle("child", child),
		{ x: 200, y: 20, width: 50, height: 50 }, base);
	bounds("rotated unclipped AABB", requireHandle("rotated", rotated),
		{ x: 50, y: 90, width: 20, height: 80 });
	bounds("rotated logical layout", requireHandle("rotated", rotated),
		{ x: 20, y: 120, width: 80, height: 20 }, base);
	bounds("offscreen scroll child unclipped", requireHandle("band", band),
		{ x: 350, y: 320, width: 50, height: 40 });
	bounds("valid zero window bounds", requireHandle("zero", zero),
		{ x: 0, y: 0, width: 0, height: 0 });
	bounds("valid zero logical bounds", requireHandle("zero", zero),
		{ x: 0, y: 0, width: 0, height: 0 }, base);
	bounds("self layout", requireHandle("scaled", scaled),
		{ x: 0, y: 0, width: 100, height: 100 }, requireHandle("scaled", scaled));
	layoutFails("unrelated ancestor", requireHandle("plain", plain), requireHandle("scaled", scaled));
	layoutFails("descendant is not ancestor", requireHandle("scaled", scaled), requireHandle("child", child));
	bounds("display none window answers zeros", requireHandle("hidden", hidden),
		{ x: 0, y: 0, width: 0, height: 0 });
	layoutFails("display none layout", requireHandle("hidden", hidden), base);
	expect("queries answer before the call returns", completed === requested, `${completed}/${requested} callbacks`);
	setTimeout(afterInitial, 400);
}

function afterInitial(): void {
	delivered("initial queries all delivered once");
	if (scroll === null) { throw "Missing public ScrollView ref"; }
	(scroll as ScrollViewHandle).scrollTo({ y: 100, animated: false });
	bounds("scrolled child window points", requireHandle("band", band),
		{ x: 350, y: 220, width: 50, height: 40 });
	bounds("scroll leaves logical ancestry unchanged", requireHandle("band", band),
		{ x: 10, y: 300, width: 50, height: 40 }, scroll as ScrollViewHandle);
	bounds("scroll leaves root logical layout unchanged", requireHandle("band", band),
		{ x: 350, y: 320, width: 50, height: 40 }, requireHandle("root", root));
	setTimeout(beforeDisposal, 400);
}

function beforeDisposal(): void {
	directBounds("band", "350,220,50,40");
	delivered("scrolled queries all delivered once");
	const target = requireHandle("disposable", disposable);
	const base = requireHandle("root", root);
	const survivor = requireHandle("plain", plain);
	setVisible(false);
	expect("disposal ran", disposed, `${disposed}`);
	bounds("surviving query after disposal", survivor,
		{ x: 20, y: 30, width: 100, height: 50 });
	bounds("window query after unmount answers zeros", target, { x: 0, y: 0, width: 0, height: 0 });
	layoutFails("layout query after unmount calls onFail", target, base);
	layoutFails("layout query after ancestor unmount calls onFail", survivor, target);
	setTimeout(afterDisposal, 400);
}

function afterDisposal(): void {
	delivered("surviving query delivered after disposal");
	harnessHide(TITLE, "plain");
	directBounds("plain", "0");
	const detached = harnessMeasureDetached();
	directChecks += 1;
	expect("native export detached", detached === -1, `${detached}, want -1`);
	expect("all original native export controls retained", directChecks === 9, `${directChecks}/9`);
	console.log(`checks ${checks}, callbacks ${completed}/${requested}, failures ${failures}`);
	exit(failures);
}

const checking = harnessIsCheck() !== 0;
const options = nativeWindowOptions(TITLE, 480, 320);
options.topmost = checking;
exit(runNativeWindow(options, App, checking ? (): void => {
	setTimeout(atStart, 700);
	setTimeout((): void => {
		console.log(`FAIL measurement timeout: callbacks ${completed}/${requested}`);
		exit(2);
	}, 8000);
} : null));
