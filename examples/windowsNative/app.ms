// Nested Views on DirectComposition through the native host, in a Win32 harness that plays Ion's part.
//   msc build examples/windowsNative/app.ms --output=out/windowsNative.exe
//   out/windowsNative.exe            opens the window
//   out/windowsNative.exe --check    samples its own pixels and exits 0 when every one matches

import "../../src/platform/windows/library";
import { runApp } from "../../src/platform/native/host";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { View } from "../../src/components/primitives";
import { harnessStart, harnessExpect, harnessRun } from "./harness.h";
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
	base: { width: 600, height: 320, backgroundColor: "#101820" },
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
	</View>;
}

harnessStart(600, 320);
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
runApp(App);
exit(harnessRun());
