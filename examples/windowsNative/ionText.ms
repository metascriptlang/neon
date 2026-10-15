// The same Views and Text as text.ms, in an Ion window with no webview.
//   msc build examples/windowsNative/ionText.ms --output=out/windowsIonText.exe
//   out/windowsIonText.exe            opens the window
//   out/windowsIonText.exe --check    samples its own pixels, compares layout sizes with a DirectWrite measurement, exits 0 when all hold

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/windows/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text } from "../../src/components/primitives";
import { harnessIsCheck, harnessExpect, harnessLayout, harnessExpectCentre, harnessExpectCount, harnessExpectSize, harnessSample } from "./harness.h";
import { exit } from "std/process";

when (windows) {
	@compile("./harness.cpp");
	@passL("-ld3d11");
	@passL("-ld2d1");
	@passL("-ldcomp");
	@passL("-ldwmapi");
	@passL("-lgdi32");
	@passL("-ldwrite");
}

const styles = createStyles({
	base: { width: 640, height: 360, backgroundColor: "#101820" },
	panel: { position: "absolute", left: 20, top: 20, width: 340, height: 140, flexDirection: "row", alignItems: "flex-start", backgroundColor: "#1c73d9" },
	wrapPanel: { position: "absolute", left: 380, top: 20, width: 240, height: 140, backgroundColor: "#2ecc71" },
	alignPanel: { position: "absolute", left: 20, top: 180, width: 300, height: 100, backgroundColor: "#8e44ad" },
	big: { marginLeft: 20, marginTop: 10 },
	hello: { marginLeft: 30, marginTop: 20 },
	wrapped: { marginLeft: 20, marginTop: 20, alignSelf: "flex-start", maxWidth: 200 },
	bigText: { color: "#ffffff", fontSize: 96, fontWeight: "bold" },
	helloText: { color: "#ffd23f", fontSize: 32 },
	wrapText: { color: "#101820", fontSize: 20 },
	rightText: { color: "#ffffff", fontSize: 24, textAlign: "right" },
	updatePanel: { position: "absolute", left: 340, top: 180, width: 280, height: 100, backgroundColor: "#34495e" },
	before: { color: "#ff0000", fontSize: 28 },
	after: { color: "#00ffaa", fontSize: 28 },
});

function layout(name: string): (e: NeonEvent) => void {
	return (e: NeonEvent): void => { harnessLayout(name, e.width as float32, e.height as float32); };
}

const [updated, setUpdated] = createSignal(false);

function App(): NeonNode {
	return <View style={styles.base}>
		<View style={styles.panel}>
			<View style={styles.big} onLayout={layout("big")}>
				<Text style={styles.bigText}>I</Text>
			</View>
			<View style={styles.hello} onLayout={layout("hello")}>
				<Text style={styles.helloText}>Hello Windows</Text>
			</View>
		</View>
		<View style={styles.wrapPanel}>
			<View style={styles.wrapped} onLayout={layout("wrapped")}>
				<Text style={styles.wrapText}>The quick brown fox jumps over the lazy dog</Text>
			</View>
		</View>
		<View style={styles.alignPanel}>
			<Text style={styles.rightText}>right</Text>
		</View>
		<View style={styles.updatePanel}>
			<Text style={updated() ? styles.after : styles.before}>{updated() ? "Updated text" : "A"}</Text>
		</View>
	</View>;
}

const TITLE = "Neon text on Ion";
const check = harnessIsCheck() !== 0;

if (check) {
	harnessExpect("base", 600, 340, 16, 24, 32);
	harnessExpect("panel outside text", 340, 150, 28, 115, 217);
	harnessExpect("text box corner shows panel", 41, 31, 28, 115, 217);
	harnessExpectCentre("stem of a bold I", "big", 40, 30, 255, 255, 255);
	harnessExpectCount("hello pixels", 90, 40, 260, 60, 255, 210, 63, 60, 300, 100000);
	harnessExpectCount("wrapped text pixels", 400, 40, 200, 100, 16, 24, 32, 60, 300, 100000);
	harnessExpectCount("right text, right half", 170, 190, 150, 90, 255, 255, 255, 60, 100, 100000);
	harnessExpectCount("right text, left half", 20, 180, 150, 100, 255, 255, 255, 60, 0, 0);
	harnessExpectCount("replaced text is gone", 340, 180, 280, 100, 255, 0, 0, 60, 0, 0);
	harnessExpectCount("updated text pixels", 340, 180, 280, 100, 0, 255, 170, 60, 300, 100000);
	harnessExpectSize("big", "I", 96, 1, 640);
	harnessExpectSize("hello", "Hello Windows", 32, 0, 640);
	harnessExpectSize("wrapped", "The quick brown fox jumps over the lazy dog", 20, 0, 200);
}

setTimeout((): void => { setUpdated(true); }, 100);
const options = nativeWindowOptions(TITLE, 640, 360);
options.topmost = check;
options.decorations = !check;
exit(runNativeWindow(options, App, check ? (): void => {
	setTimeout((): void => { exit(harnessSample(TITLE)); }, 700);
} : null));
