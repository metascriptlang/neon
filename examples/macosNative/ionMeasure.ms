// The native geometry exports of the macOS bridge (niMeasureInWindow and niMeasurementX/Y/W/H): a view's bounds in the
// window's content, top-left origin, in points, with its painted transforms and its ancestors' scroll applied.
//   msc build examples/macosNative/ionMeasure.ms --output=out/macosIonMeasure
//   out/macosIonMeasure --check    measures each labelled view through the harness and exits 0 when every bound holds

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { View, ScrollView, ScrollViewHandle } from "../../src/components/primitives";
import { harnessIsCheck, harnessMeasure, harnessMeasureDetached, harnessHide } from "./harness.h";
import { exit } from "std/process";

when (macos) {
	@compile("./harness.m", "-fobjc-arc");
}

const styles = createStyles({
	base: { width: 480, height: 320, backgroundColor: "#101820" },
	plain: { position: "absolute", left: 20, top: 30, width: 100, height: 50, backgroundColor: "#2e86de" },
	scaled: { position: "absolute", left: 200, top: 20, width: 100, height: 100, backgroundColor: "#27ae60", transform: "scale(0.5)" },
	scaledChild: { position: "absolute", left: 0, top: 0, width: 50, height: 50, backgroundColor: "#e74c3c" },
	rotated: { position: "absolute", left: 20, top: 120, width: 80, height: 20, backgroundColor: "#9b59b6", transform: "rotate(90deg)" },
	scroll: { position: "absolute", left: 340, top: 20, width: 120, height: 200, backgroundColor: "#34495e" },
	content: { height: 600 },
	band: { position: "absolute", left: 10, top: 300, width: 50, height: 40, backgroundColor: "#f1c40f" },
});

let handle: ScrollViewHandle | null = null;

function App(): NeonNode {
	return <View style={styles.base}>
		<View style={styles.plain} accessibilityLabel="plain" />
		<View style={styles.scaled} accessibilityLabel="scaled">
			<View style={styles.scaledChild} accessibilityLabel="scaledChild" />
		</View>
		<View style={styles.rotated} accessibilityLabel="rotated" />
		<ScrollView style={styles.scroll} ref={(h: ScrollViewHandle): void => { handle = h; }}>
			<View style={styles.content}>
				<View style={styles.band} accessibilityLabel="band" />
			</View>
		</ScrollView>
	</View>;
}

const TITLE = "Neon measure on Ion";
let failures = 0;

function measured(label: string): string {
	const got: string = harnessMeasure(TITLE, label);
	return got;
}

function expect(label: string, want: string): void {
	const got = measured(label);
	const ok = got === want;
	console.log(`${ok ? "ok  " : "FAIL"} ${label}: ${got}, want ${want}`);
	if (!ok) { failures += 1; }
}

function check(): void {
	expect("plain", "20,30,100,50");
	expect("scaled", "225,45,50,50");
	expect("scaledChild", "225,45,25,25");
	expect("rotated", "50,90,20,80");
	expect("band", "350,320,50,40");
	(handle as ScrollViewHandle).scrollTo({ y: 100, animated: false });
	setTimeout((): void => {
		expect("band", "350,220,50,40");
		harnessHide(TITLE, "plain");
		expect("plain", "0");
		const detached = harnessMeasureDetached();
		console.log(`${detached === -1 ? "ok  " : "FAIL"} a view outside the window: ${detached}, want -1`);
		if (detached !== -1) { failures += 1; }
		console.log(`failures ${failures}`);
		exit(failures);
	}, 400);
}

const options = nativeWindowOptions(TITLE, 480, 320);
options.topmost = harnessIsCheck() !== 0;
exit(runNativeWindow(options, App, harnessIsCheck() !== 0 ? (): void => {
	setTimeout(check, 700);
} : null));
