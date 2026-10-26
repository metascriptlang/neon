// An ActivityIndicator in an Ion window: the two sizes, colour, animating and hidesWhenStopped.
//   msc build examples/windowsNative/ionActivityIndicator.ms --output=out/windowsIonActivityIndicator.exe
//   out/windowsIonActivityIndicator.exe            opens the window with the indicators spinning
//   out/windowsIonActivityIndicator.exe --check    samples the frozen rings, compares captures of the spinning and the stopped
//                                                  ones and exits 0 when all match

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/windows/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { View } from "../../src/components/primitives";
import { ActivityIndicator } from "../../src/components/activityIndicator";
import { harnessIsCheck, harnessExpect, harnessExpectCount, harnessSample, harnessShot, harnessCompareShots } from "./harness.h";
import { Window } from "../../../ion/src/index";
import { exit } from "std/process";

when (windows) {
	@compile("./harness.cpp");
	@passL("-ld3d11");
	@passL("-ld2d1");
	@passL("-ldcomp");
	@passL("-ldwmapi");
	@passL("-lgdi32");
}

const styles = createStyles({
	base: { flexGrow: 1, backgroundColor: "#101820" },
	small: { position: "absolute", left: 20, top: 20 },
	spin: { position: "absolute", left: 80, top: 20 },
	hide: { position: "absolute", left: 140, top: 20 },
	frozenLarge: { position: "absolute", left: 200, top: 20 },
	frozenSmall: { position: "absolute", left: 260, top: 20 },
	hidden: { position: "absolute", left: 320, top: 20 },
});

const [spinning, setSpinning] = createSignal(true);
const [hideable, setHideable] = createSignal(true);

function App(): NeonNode {
	return <View style={styles.base}>
		<ActivityIndicator style={styles.small} size="small" color="#e63a3a" />
		<ActivityIndicator style={styles.spin} size="large" color="#1c73d9" animating={spinning()} hidesWhenStopped={false} />
		<ActivityIndicator style={styles.hide} size="large" color="#2ecc71" animating={hideable()} />
		<ActivityIndicator style={styles.frozenLarge} size="large" color="#f1c40f" animating={false} hidesWhenStopped={false} />
		<ActivityIndicator style={styles.frozenSmall} size="small" color="#e67e22" animating={false} hidesWhenStopped={false} />
		<ActivityIndicator style={styles.hidden} size="large" color="#ff00ff" animating={false} />
	</View>;
}

const TITLE = "Neon activity indicator on Ion";
const check = harnessIsCheck() !== 0;
const MOTION = 20;

function shot(name: string): int32 {
	return harnessShot(TITLE, name, 80, 20, 36, 36);
}

// RNW's ring at the stopped phase 0.7 (CompositionContextHelper.cpp:1869) is an arc from 252 to 360 degrees, clockwise
// from 3 o'clock: over the top and down to the right. Radius 35/80 of the box, stroke 7.5/80.
function atStart(): void {
	harnessExpect("large top", 218, 22, 241, 196, 15);
	harnessExpect("large right", 233, 37, 241, 196, 15);
	harnessExpect("large left: no arc", 202, 38, 16, 24, 32);
	harnessExpect("large bottom: no arc", 218, 54, 16, 24, 32);
	harnessExpect("large above its box", 218, 19, 16, 24, 32);
	harnessExpect("large beyond the right", 237, 37, 16, 24, 32);
	harnessExpect("small top", 270, 21, 230, 126, 34);
	harnessExpect("small right", 278, 29, 230, 126, 34);
	harnessExpect("small left: no arc", 262, 30, 16, 24, 32);
	harnessExpect("small bottom: no arc", 270, 39, 16, 24, 32);
	harnessExpect("small above its box", 270, 18, 16, 24, 32);
	harnessExpectCount("small spinner draws", 20, 20, 20, 20, 230, 58, 58, 40, 12, 400);
	harnessExpectCount("hides: shown while animating", 140, 20, 36, 36, 46, 204, 113, 40, 20, 1296);
	harnessExpectCount("hidden at rest", 320, 20, 36, 36, 255, 0, 255, 40, 0, 0);
	const failures = harnessSample(TITLE) + shot("spinA");
	if (failures !== 0) { exit(failures); }
	setTimeout(spinning2, 300);
}

function spinning2(): void {
	const failures = shot("spinB") + harnessCompareShots("spinA", "spinB", 0, MOTION);
	if (failures !== 0) { exit(failures); }
	setSpinning(false);
	setHideable(false);
	setTimeout(stopped1, 400);
}

function stopped1(): void {
	const failures = shot("stopA");
	if (failures !== 0) { exit(failures); }
	setTimeout(stopped2, 300);
}

function stopped2(): void {
	harnessExpectCount("hides: hidden once stopped", 140, 20, 36, 36, 46, 204, 113, 40, 0, 0);
	harnessExpectCount("stopped ring stays", 80, 20, 36, 36, 28, 115, 217, 40, 20, 1296);
	const failures = shot("stopB") + harnessCompareShots("stopA", "stopB", 1, 0) + harnessSample(TITLE);
	if (failures !== 0) { exit(failures); }
	setSpinning(true);
	setHideable(true);
	setTimeout(resumed, 300);
}

function resumed(): void {
	harnessExpectCount("hides: shown again", 140, 20, 36, 36, 46, 204, 113, 40, 20, 1296);
	const failures = shot("spinC") + harnessCompareShots("stopB", "spinC", 0, MOTION) + harnessSample(TITLE);
	exit(failures);
}

const options = nativeWindowOptions(TITLE, 400, 100);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (win: Window): void => { setTimeout(atStart, 700); } : null));
