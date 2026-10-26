// Image.getSize and Image.prefetch in an Ion window: a local PNG reports its exact pixel size, a missing file rejects,
// and with --network an https PNG is downloaded off the UI thread, reports its size through getSize and onLoad, and a
// missing URL reports an error. Run it from the Neon checkout root.
//   msc build examples/windowsNative/ionImageSize.ms --output=out/windowsIonImageSize.exe
//   out/windowsIonImageSize.exe --check             checks the local cases and exits 0 when all hold
//   out/windowsIonImageSize.exe --check --network   also checks the https cases (needs internet)

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/windows/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View } from "../../src/components/primitives";
import { Image, ImageLoader } from "../../src/components/image";
import { harnessIsCheck, harnessHasFlag, harnessSample, harnessFileUri } from "./harness.h";
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
const MISSING = harnessFileUri("examples/windowsNative/missing.png");
const REMOTE = "https://raw.githubusercontent.com/github/explore/main/topics/javascript/javascript.png";
const REMOTE_MISSING = "https://raw.githubusercontent.com/github/explore/main/topics/javascript/neon-missing.png";

const TITLE = "Neon image size on Ion";
const check = harnessIsCheck() !== 0;
const network = harnessHasFlag("--network") !== 0;

const styles = createStyles({
	base: { width: 200, height: 100, backgroundColor: "#101820" },
	remote: { position: "absolute", left: 10, top: 10, width: 80, height: 80 },
	absent: { position: "absolute", left: 110, top: 10, width: 80, height: 80 },
});

const answers: Map<string, string> = new Map();

function answer(name: string, text: string): void {
	answers.set(name, text);
	console.log(`${name} ${text}`);
}

function sizeOf(name: string, uri: string): void {
	ImageLoader.getSize(uri, (w: number, h: number): void => { answer(name, `${w}x${h}`); }, (e: Error): void => { answer(name, `error ${e.message}`); });
}

function loaded(name: string): (e: NeonEvent) => void {
	return (e: NeonEvent): void => { answer(name, `${e.width}x${e.height}`); };
}

function failed(name: string): (e: NeonEvent) => void {
	return (e: NeonEvent): void => { answer(name, `error ${e.value}`); };
}

function App(): NeonNode {
	return <View style={styles.base}>
		{network ? <Image style={styles.remote} source={{ uri: REMOTE }} onLoad={loaded("view")} onError={failed("view")} /> : null}
		{network ? <Image style={styles.absent} source={{ uri: REMOTE_MISSING }} onLoad={loaded("viewMissing")} onError={failed("viewMissing")} /> : null}
	</View>;
}

let failures = 0;

function seen(name: string): string {
	return answers.has(name) ? answers.get(name) as string : "<none>";
}

function expect(what: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "ok  " : "FAIL"} ${what}: ${detail}`);
	if (!ok) { failures += 1; }
}

function isError(name: string): boolean {
	return seen(name).startsWith("error ") && seen(name).length > 6;
}

function verify(): void {
	expect("getSize of a local PNG is its pixel size", seen("split") === "4x4", seen("split"));
	expect("getSize of a second PNG", seen("wide") === "4x2", seen("wide"));
	expect("getSize of a missing file rejects", isError("missing"), seen("missing"));
	if (network) {
		expect("getSize of an https PNG", seen("remote") === "288x288", seen("remote"));
		expect("getSize of a missing https URL rejects", isError("remoteMissing"), seen("remoteMissing"));
		expect("an https Image reports onLoad at its pixel size", seen("view") === "288x288", seen("view"));
		expect("a missing https Image reports onError", isError("viewMissing"), seen("viewMissing"));
		expect("prefetch of an https PNG resolves true", seen("prefetch") === "true", seen("prefetch"));
	}
	failures += harnessSample(TITLE);
	console.log(`failures ${failures}`);
	exit(failures);
}

const settled = (): boolean => {
	const local = answers.has("split") && answers.has("wide") && answers.has("missing");
	return local && (!network || (answers.has("remote") && answers.has("remoteMissing") && answers.has("view") && answers.has("viewMissing") && answers.has("prefetch")));
};

let waited = 0;
function waitThenVerify(): void {
	waited += 250;
	if (settled() || waited >= 20000) { verify(); return; }
	setTimeout(waitThenVerify, 250);
}

function ask(): void {
	sizeOf("split", SPLIT);
	sizeOf("wide", WIDE);
	sizeOf("missing", MISSING);
	if (network) {
		sizeOf("remote", REMOTE);
		sizeOf("remoteMissing", REMOTE_MISSING);
		ImageLoader.prefetch(REMOTE).then((ok: boolean): void => { answer("prefetch", ok ? "true" : "false"); });
	}
}

const options = nativeWindowOptions(TITLE, 200, 100);
options.topmost = check;
exit(runNativeWindow(options, App, (): void => {
	ask();
	if (check) { setTimeout(waitThenVerify, 250); }
}));
