// Switch, ActivityIndicator and Image in a macOS Ion window: NSSwitch, a spinning NSProgressIndicator and a layer
// drawing the decoded image, as RN macOS's RCTUIKit shims do.
//   msc build examples/macosNative/ionControls.ms --output=out/macosIonControls
//   out/macosIonControls            opens the window and logs each switch flip, load and error
//   out/macosIonControls --check    clicks the switches through AppKit events, samples the images and the spinner,
//                                   and exits 0 when every expectation holds

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View } from "../../src/components/primitives";
import { Switch } from "../../src/components/switch";
import { ActivityIndicator } from "../../src/components/activityIndicator";
import { Image, ImageLoader } from "../../src/components/image";
import { harnessIsCheck, harnessExpect, harnessExpectCount, harnessSample, harnessClick, harnessSwitchStates } from "./harness.h";
import { exit } from "std/process";

when (macos) {
	@compile("./harness.m", "-fobjc-arc");
}

// 4x4, the top half red and the bottom half blue; 4x2 green; an 8x8 tile of red and yellow quadrants.
const SPLIT = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAF0lEQVR4nGN47mMDRwwoHL22e3CEwgEAYsIYCfpgwlgAAAAASUVORK5CYII=";
const WIDE = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAIAAADwyuo0AAAAEElEQVR4nGNQX5cARwzIHAB72gmpivMj/gAAAABJRU5ErkJggg==";
const TILE = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAHElEQVR4nGN47mMDRx+P8MMRAxUlkDnIiqgoAQAyQGZhSkCjggAAAABJRU5ErkJggg==";
const MISSING = "file:///nonexistent/neon-macos-check.png";

const styles = createStyles({
	base: { width: 480, height: 320, backgroundColor: "#101820" },
	cover: { position: "absolute", left: 20, top: 20, width: 100, height: 100 },
	contain: { position: "absolute", left: 140, top: 20, width: 100, height: 100, backgroundColor: "#ffffff" },
	repeat: { position: "absolute", left: 260, top: 20, width: 40, height: 40 },
	blurred: { position: "absolute", left: 320, top: 20, width: 100, height: 100 },
	missing: { position: "absolute", left: 440, top: 20, width: 20, height: 20 },
	defaulted: { position: "absolute", left: 440, top: 60, width: 30, height: 30 },
	controlled: { position: "absolute", left: 20, top: 160 },
	fixed: { position: "absolute", left: 120, top: 160 },
	disabled: { position: "absolute", left: 220, top: 160 },
	spinner: { position: "absolute", left: 20, top: 230 },
	stopping: { position: "absolute", left: 120, top: 230 },
});

const [on, setOn] = createSignal(false);
const [spinning, setSpinning] = createSignal(true);
const flips: string[] = [];
const loads: Map<string, string> = new Map();
const errors: Map<string, string> = new Map();
let switchWidth: number = 0;
let switchHeight: number = 0;

function flipped(name: string): (v: boolean) => void {
	return (v: boolean): void => {
		flips.push(`${name}=${v}`);
		console.log(`flip ${name} ${v}`);
	};
}

function loaded(name: string): (e: NeonEvent) => void {
	return (e: NeonEvent): void => {
		loads.set(name, `${e.width}x${e.height}`);
		console.log(`load ${name} ${e.width}x${e.height}`);
	};
}

function failed(name: string): (e: NeonEvent) => void {
	return (e: NeonEvent): void => {
		errors.set(name, e.value);
		console.log(`error ${name} "${e.value}"`);
	};
}

function App(): NeonNode {
	return <View style={styles.base}>
		<Image style={styles.cover} source={{ uri: SPLIT }} onLoad={loaded("cover")} onError={failed("cover")} />
		<Image style={styles.contain} source={{ uri: WIDE }} resizeMode="contain" onLoad={loaded("contain")} onError={failed("contain")} />
		<Image style={styles.repeat} source={{ uri: TILE }} resizeMode="repeat" onLoad={loaded("repeat")} onError={failed("repeat")} />
		<Image style={styles.blurred} source={{ uri: SPLIT }} blurRadius={8} onLoad={loaded("blurred")} onError={failed("blurred")} />
		<Image style={styles.missing} source={{ uri: MISSING }} onLoad={loaded("missing")} onError={failed("missing")} />
		<Image style={styles.defaulted} source={{ uri: MISSING }} defaultSource={{ uri: SPLIT }} onLoad={loaded("defaulted")}
			onError={failed("defaulted")} />
		<Switch style={styles.controlled} value={on()} onValueChange={(v: boolean): void => {
			flipped("controlled")(v);
			setOn(v);
		}} onLayout={(e: NeonEvent): void => {
			switchWidth = e.width;
			switchHeight = e.height;
		}} />
		<Switch style={styles.fixed} value={false} onValueChange={flipped("fixed")} />
		<Switch style={styles.disabled} value={true} disabled={true} onValueChange={flipped("disabled")} />
		<ActivityIndicator style={styles.spinner} size="large" color="#e74c3c" />
		<ActivityIndicator style={styles.stopping} size="large" animating={spinning()} />
	</View>;
}

const TITLE = "Neon controls on Ion";
const check = harnessIsCheck() !== 0;
let failures = 0;

function expect(what: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "ok  " : "FAIL"} ${what}: ${detail}`);
	if (!ok) { failures += 1; }
}

function click(x: number, y: number): void {
	harnessClick(TITLE, x as int32, y as int32);
}

function switches(): string {
	const states: string = harnessSwitchStates(TITLE);
	return states;
}

function seen(map: Map<string, string>, name: string): string {
	return map.has(name) ? map.get(name) as string : "<none>";
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

let sized = "<none>";
let missingSize = "<none>";

steps.push((): void => {
	ImageLoader.getSize(WIDE, (w: number, h: number): void => { sized = `${w}x${h}`; });
	ImageLoader.getSize(MISSING, (w: number, h: number): void => { missingSize = `${w}x${h}`; }, (e: Error): void => { missingSize = e.message; });
});
steps.push((): void => {
	expect("Image.getSize reads the pixel size", sized === "4x2", sized);
	expect("Image.getSize reports a missing file", missingSize !== "<none>" && missingSize !== "0x0", missingSize);
	expect("cover loaded at its pixel size", seen(loads, "cover") === "4x4", seen(loads, "cover"));
	expect("contain loaded", seen(loads, "contain") === "4x2", seen(loads, "contain"));
	expect("repeat loaded", seen(loads, "repeat") === "8x8", seen(loads, "repeat"));
	expect("blurred loaded", seen(loads, "blurred") === "4x4", seen(loads, "blurred"));
	expect("a missing file reports an error", seen(errors, "missing") !== "<none>" && !loads.has("missing"), seen(errors, "missing"));
	expect("a missing source behind a defaultSource reports an error", seen(errors, "defaulted") !== "<none>" && !loads.has("defaulted"),
		seen(errors, "defaulted"));
	expect("the switch measured its NSSwitch", switchWidth > 20 && switchHeight > 10, `${switchWidth}x${switchHeight}`);
	harnessExpect("cover top is red", 70, 40, 231, 76, 60);
	harnessExpect("cover bottom is blue", 70, 100, 46, 134, 222);
	harnessExpect("the defaultSource stays drawn", 455, 64, 231, 76, 60);
	harnessExpect("contain letterbox shows the background", 190, 30, 255, 255, 255);
	harnessExpect("contain draws the image", 190, 70, 39, 174, 96);
	harnessExpectCount("repeat tiles red", 260, 20, 40, 40, 231, 76, 60, 30, 400, 1200);
	harnessExpectCount("repeat tiles yellow", 260, 20, 40, 40, 241, 196, 15, 30, 400, 1200);
	harnessExpectCount("blur leaves no pure red at the edge", 330, 60, 80, 20, 231, 76, 60, 12, 0, 0);
	harnessExpectCount("blur leaves no pure blue at the edge", 330, 60, 80, 20, 46, 134, 222, 12, 0, 0);
	harnessExpectCount("the blurred image covers its box", 320, 20, 100, 100, 16, 24, 32, 30, 0, 0);
	harnessExpectCount("the spinner draws", 20, 230, 36, 36, 16, 24, 32, 6, 0, 1200);
	failures += harnessSample(TITLE);
	expect("the switches show their values", switches() === "001", switches());
	click(20 + switchWidth / 2, 160 + switchHeight / 2);
});
steps.push((): void => {
	expect("a click flips the controlled switch", flips.join(",") === "controlled=true" && on(), flips.join(","));
	expect("the controlled switch stays on", switches() === "101", switches());
	click(120 + switchWidth / 2, 160 + switchHeight / 2);
});
steps.push((): void => {
	expect("the fixed switch reports the flip", flips.join(",") === "controlled=true,fixed=true", flips.join(","));
	expect("the fixed switch returns to its value", switches() === "101", switches());
	click(220 + switchWidth / 2, 160 + switchHeight / 2);
});
steps.push((): void => {
	expect("a disabled switch ignores the click", flips.join(",") === "controlled=true,fixed=true" && switches() === "101", `${flips.join(",")} ${switches()}`);
	setSpinning(false);
});
steps.push((): void => {
	harnessExpectCount("a stopped spinner hides", 120, 230, 36, 36, 16, 24, 32, 6, 1296, 1296);
	failures += harnessSample(TITLE);
});

const options = nativeWindowOptions(TITLE, 480, 320);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (): void => {
	setTimeout((): void => { run(0); }, 1000);
} : null));
