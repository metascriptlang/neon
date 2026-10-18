import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { NeonNode } from "../../src/render/node";
import { View, Text } from "../../src/components/primitives";
import { exit } from "std/process";

function App(): NeonNode {
	return <View><Text>hi</Text></View>;
}

exit(runNativeWindow(nativeWindowOptions("minimal", 320, 200), App, null));
