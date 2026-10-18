// Svg in a macOS Ion window: the display list drawn by Core Graphics in a flipped NSView, as on iOS.
//   msc build examples/macosNative/ionSvg.ms --output=out/macosIonSvg
//   out/macosIonSvg            opens the window
//   out/macosIonSvg --check    samples the shapes, the gradient, the stroke and the text, grows the circle, samples
//                              again, and exits 0 when every expectation holds

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View } from "../../src/components/primitives";
import { Svg, Rect, Circle, Path, Defs, LinearGradient, Stop, Text } from "../../src/components/svg/elements";
import { harnessIsCheck, harnessExpect, harnessExpectCount, harnessSample } from "./harness.h";
import { exit } from "std/process";

when (macos) {
	@compile("./harness.m", "-fobjc-arc");
}

const styles = createStyles({
	base: { width: 480, height: 320, backgroundColor: "#101820" },
	shapes: { position: "absolute", left: 20, top: 20 },
	gradient: { position: "absolute", left: 240, top: 20 },
	lines: { position: "absolute", left: 20, top: 140 },
});

const [radius, setRadius] = createSignal<float64>(3);
let shapesLayout = "<none>";

function App(): NeonNode {
	return <View style={styles.base}>
		<Svg style={styles.shapes} width={200} height={100} viewBox="0 0 20 10" onLayout={(e: NeonEvent): void => {
			shapesLayout = `${e.width}x${e.height}`;
		}}>
			<Rect x={0} y={0} width={10} height={10} fill="#e74c3c" />
			<Circle cx={15} cy={5} r={radius()} fill="#2e86de" />
		</Svg>
		<Svg style={styles.gradient} width={200} height={100}>
			<Defs>
				<LinearGradient id="fade" x1="0%" y1="0%" x2="100%" y2="0%">
					<Stop offset="0%" stopColor="#e74c3c" />
					<Stop offset="100%" stopColor="#2e86de" />
				</LinearGradient>
			</Defs>
			<Rect width={200} height={100} fill="url(#fade)" />
		</Svg>
		<Svg style={styles.lines} width={440} height={80}>
			<Path d="M 0 20 L 200 20" stroke="#27ae60" strokeWidth={10} />
			<Text x={240} y={40} fontSize={32} fill="#f1c40f">Neon</Text>
		</Svg>
	</View>;
}

const TITLE = "Neon Svg on Ion";
const check = harnessIsCheck() !== 0;
let failures = 0;

function expect(what: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "ok  " : "FAIL"} ${what}: ${detail}`);
	if (!ok) { failures += 1; }
}

const steps: (() => void)[] = [];

function run(at: number): void {
	if (at >= steps.length) {
		console.log(`failures ${failures}`);
		exit(failures);
		return;
	}
	steps[at]();
	setTimeout((): void => { run(at + 1); }, 600);
}

steps.push((): void => {
	expect("the Svg is laid out by its width and height", shapesLayout === "200x100", shapesLayout);
	harnessExpect("the viewBox scales the rect", 70, 70, 231, 76, 60);
	harnessExpect("the circle centre", 170, 70, 46, 134, 222);
	harnessExpect("outside the small circle", 210, 70, 16, 24, 32);
	harnessExpectCount("the gradient starts red", 242, 30, 6, 80, 231, 76, 60, 30, 400, 480);
	harnessExpectCount("the gradient ends blue", 432, 30, 6, 80, 46, 134, 222, 30, 400, 480);
	harnessExpectCount("the gradient has no red at its end", 432, 30, 6, 80, 231, 76, 60, 30, 0, 0);
	harnessExpect("the stroke draws", 120, 160, 39, 174, 96);
	harnessExpect("the stroke keeps its width", 120, 170, 16, 24, 32);
	harnessExpectCount("the text draws above its baseline", 260, 150, 120, 31, 241, 196, 15, 30, 40, 3720);
	harnessExpectCount("the text draws upright", 260, 183, 120, 20, 241, 196, 15, 30, 0, 0);
	failures += harnessSample(TITLE);
	setRadius(5);
});
steps.push((): void => {
	harnessExpect("the grown circle reaches further", 210, 70, 46, 134, 222);
	harnessExpect("the rect stays", 70, 70, 231, 76, 60);
	failures += harnessSample(TITLE);
});

const options = nativeWindowOptions(TITLE, 480, 320);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (): void => {
	setTimeout((): void => { run(0); }, 1000);
} : null));
