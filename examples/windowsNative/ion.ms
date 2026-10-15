// The same Views as app.ms, in an Ion window with no webview.
//   msc build examples/windowsNative/ion.ms --output=out/windowsIon.exe
//   out/windowsIon.exe            opens the window
//   out/windowsIon.exe --check    samples its own pixels, resizes its window, samples again, and exits 0 when every one matches

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/windows/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { View } from "../../src/components/primitives";
import { harnessIsCheck, harnessExpect, harnessSample, harnessResizeClient } from "./harness.h";
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
	pin: { position: "absolute", right: 10, bottom: 10, width: 40, height: 40, backgroundColor: "#ffd23f" },
	parent: { marginLeft: 40, marginTop: 30, width: 420, height: 200, flexDirection: "row", backgroundColor: "#1c73d9", borderRadius: 24 },
	rounded: { marginLeft: 20, marginTop: 20, width: 120, height: 100, backgroundColor: "#e63a3a", borderRadius: 30 },
	faded: { marginLeft: 20, marginTop: 20, width: 100, height: 100, backgroundColor: "#ffffff", opacity: 0.5 },
	tinted: { marginLeft: 20, marginTop: 20, width: 100, height: 100, backgroundColor: "rgba(0, 0, 0, 0.5)" },
	scaled: { position: "absolute", left: 480, top: 30, width: 100, height: 100, backgroundColor: "#2ecc71", transform: "scale(0.5)", borderRadius: 30 },
});

function App(): NeonNode {
	return <View style={styles.base}>
		<View style={styles.parent}>
			<View style={styles.rounded} />
			<View style={styles.faded} />
			<View style={styles.tinted} />
		</View>
		<View style={styles.scaled} />
		<View style={styles.pin} />
	</View>;
}

const TITLE = "Neon on Ion";
const check = harnessIsCheck() !== 0;

if (check) {
	harnessExpect("base", 10, 10, 16, 24, 32);
	harnessExpect("parent corner", 42, 32, 16, 24, 32);
	harnessExpect("parent", 100, 200, 28, 115, 217);
	harnessExpect("child", 120, 100, 230, 58, 58);
	harnessExpect("child outside corner", 62, 52, 28, 115, 217);
	harnessExpect("half opacity child", 250, 100, 142, 185, 236);
	harnessExpect("half alpha background", 370, 100, 14, 58, 109);
	harnessExpect("scaled inside", 530, 80, 46, 204, 113);
	harnessExpect("scaled outside", 484, 34, 16, 24, 32);
	harnessExpect("scaled rounded inside", 510, 60, 46, 204, 113);
	harnessExpect("scaled rounded outside", 507, 57, 16, 24, 32);
	harnessExpect("pin", 570, 290, 255, 210, 63);
}

const options = nativeWindowOptions(TITLE, 600, 320);
options.topmost = check;
options.decorations = !check;
const afterResize = (): void => {
	harnessExpect("pin moved", 770, 370, 255, 210, 63);
	harnessExpect("pin's old place", 570, 290, 16, 24, 32);
	harnessExpect("new area", 700, 100, 16, 24, 32);
	harnessExpect("parent unmoved", 100, 200, 28, 115, 217);
	exit(harnessSample(TITLE));
};
exit(runNativeWindow(options, App, check ? (): void => {
	setTimeout((): void => {
		const failures = harnessSample(TITLE);
		if (failures !== 0) { exit(failures); }
		harnessResizeClient(TITLE, 800, 400);
		setTimeout(afterResize, 700);
	}, 700);
} : null));
