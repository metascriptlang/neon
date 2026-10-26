// Image in an Ion window: WIC decodes the PNG, Direct2D draws it into the view's surface in every resizeMode, onLoad
// reports the pixel size and a missing file reports onError. Run it from the Neon checkout root.
//   msc build examples/windowsNative/ionImage.ms --output=out/windowsIonImage.exe
//   out/windowsIonImage.exe            opens the window and logs each load and error
//   out/windowsIonImage.exe --check    samples its own pixels and the events it received, and exits 0 when all match

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/windows/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View } from "../../src/components/primitives";
import { Image } from "../../src/components/image";
import { harnessIsCheck, harnessExpect, harnessExpectCount, harnessSample, harnessFileUri } from "./harness.h";
import { exit } from "std/process";

when (windows) {
	@compile("./harness.cpp");
	@passL("-ld3d11");
	@passL("-ld2d1");
	@passL("-ldcomp");
	@passL("-ldwmapi");
	@passL("-lgdi32");
}

const SPLIT = harnessFileUri("examples/windowsNative/split.png");
const WIDE = harnessFileUri("examples/windowsNative/wide.png");
const TILE = harnessFileUri("examples/windowsNative/tile.png");
const MISSING = harnessFileUri("examples/windowsNative/missing.png");

const styles = createStyles({
	base: { width: 480, height: 260, backgroundColor: "#101820" },
	cover: { position: "absolute", left: 20, top: 20, width: 100, height: 100 },
	contain: { position: "absolute", left: 140, top: 20, width: 100, height: 100, backgroundColor: "#ffffff" },
	stretch: { position: "absolute", left: 260, top: 20, width: 100, height: 50 },
	center: { position: "absolute", left: 380, top: 20, width: 100, height: 100 },
	repeat: { position: "absolute", left: 20, top: 140, width: 40, height: 40 },
	missing: { position: "absolute", left: 80, top: 140, width: 20, height: 20 },
	blurred: { position: "absolute", left: 200, top: 140, width: 100, height: 100 },
});

const loads: Map<string, string> = new Map();
const errors: Map<string, string> = new Map();

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
		<Image style={styles.stretch} source={{ uri: SPLIT }} resizeMode="stretch" onLoad={loaded("stretch")} onError={failed("stretch")} />
		<Image style={styles.center} source={{ uri: WIDE }} resizeMode="center" onLoad={loaded("center")} onError={failed("center")} />
		<Image style={styles.repeat} source={{ uri: TILE }} resizeMode="repeat" onLoad={loaded("repeat")} onError={failed("repeat")} />
		<Image style={styles.missing} source={{ uri: MISSING }} onLoad={loaded("missing")} onError={failed("missing")} />
		<Image style={styles.blurred} source={{ uri: SPLIT }} blurRadius={8} onLoad={loaded("blurred")} onError={failed("blurred")} />
	</View>;
}

const TITLE = "Neon image on Ion";
const check = harnessIsCheck() !== 0;
let failures = 0;

function expect(what: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "ok  " : "FAIL"} ${what}: ${detail}`);
	if (!ok) { failures += 1; }
}

function seen(map: Map<string, string>, name: string): string {
	return map.has(name) ? map.get(name) as string : "<none>";
}

function verify(): void {
	expect("cover loaded at its pixel size", seen(loads, "cover") === "4x4", seen(loads, "cover"));
	expect("contain loaded", seen(loads, "contain") === "4x2", seen(loads, "contain"));
	expect("stretch loaded", seen(loads, "stretch") === "4x4", seen(loads, "stretch"));
	expect("center loaded", seen(loads, "center") === "4x2", seen(loads, "center"));
	expect("repeat loaded", seen(loads, "repeat") === "8x8", seen(loads, "repeat"));
	expect("blurred loaded", seen(loads, "blurred") === "4x4", seen(loads, "blurred"));
	expect("a missing file reports an error", seen(errors, "missing") !== "<none>" && !loads.has("missing"), seen(errors, "missing"));
	expect("a decoded image reports no error", errors.size === 1, `${errors.size} errors`);
	harnessExpect("cover top is red", 70, 40, 231, 76, 60);
	harnessExpect("cover bottom is blue", 70, 100, 46, 134, 222);
	harnessExpect("contain letterbox above", 190, 40, 255, 255, 255);
	harnessExpect("contain draws the image top", 190, 50, 39, 174, 96);
	harnessExpect("contain draws the image bottom", 190, 92, 39, 174, 96);
	harnessExpect("contain letterbox below", 190, 98, 255, 255, 255);
	harnessExpect("stretch top is red", 310, 30, 231, 76, 60);
	harnessExpect("stretch bottom is blue", 310, 60, 46, 134, 222);
	harnessExpect("center draws at its pixel size", 430, 70, 39, 174, 96);
	harnessExpect("center leaves the rest of the box empty", 420, 70, 16, 24, 32);
	harnessExpectCount("repeat tiles red", 20, 140, 40, 40, 231, 76, 60, 30, 400, 100000);
	harnessExpectCount("repeat tiles yellow", 20, 140, 40, 40, 241, 196, 15, 30, 400, 100000);
	harnessExpectCount("a missing image draws nothing", 80, 140, 20, 20, 16, 24, 32, 6, 400, 100000);
	harnessExpectCount("blur leaves no pure red at the seam", 210, 180, 80, 20, 231, 76, 60, 12, 0, 0);
	harnessExpectCount("blur leaves no pure blue at the seam", 210, 180, 80, 20, 46, 134, 222, 12, 0, 0);
	harnessExpectCount("the blurred image covers its box", 200, 140, 100, 100, 16, 24, 32, 30, 0, 0);
	failures += harnessSample(TITLE);
	console.log(`failures ${failures}`);
	exit(failures);
}

const options = nativeWindowOptions(TITLE, 480, 260);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (): void => {
	setTimeout(verify, 1000);
} : null));
