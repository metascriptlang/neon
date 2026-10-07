import { runApp } from "../../src/platform/native/host";
import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { Text } from "../../src/components/primitives";
import { StatusBar } from "../../src/components/statusBar";
import { SafeAreaView } from "../../src/components/safeAreaView";
import { useSafeAreaInsets } from "../../src/render/environment";
import { NeonNode } from "../../src/render/node";
import { nmTeardown, nmSystemInsets, nmTextVisualY } from "./nativeBridgeMock.h";

test "the native host publishes how far the unsafe areas reach into its root, and a translucent StatusBar takes the root edge to edge" {
	const insets = useSafeAreaInsets();
	const [clear, setClear] = createSignal(false);
	const app = (): NeonNode => <SafeAreaView style={{ flex: 1 }}>
		<StatusBar translucent={clear()} />
		<Text>safe</Text>
	</SafeAreaView>;
	runApp(app);
	nmSystemInsets(47, 0, 34, 0);
	const inside = `${insets().top}/${insets().bottom} ${nmTextVisualY("safe")}`;
	setClear(true);
	const edge = `${insets().top}/${insets().bottom} ${nmTextVisualY("safe")}`;
	setClear(false);
	const back = `${insets().top}/${insets().bottom} ${nmTextVisualY("safe")}`;
	nmTeardown();
	nmSystemInsets(0, 0, 0, 0);
	assert inside === "0/0 0", "a root inside the safe area reports no insets: " + inside;
	assert edge === "47/34 47", "edge to edge, SafeAreaView pads by the reported insets: " + edge;
	assert back === "0/0 0", "back inside the safe area: " + back;
}
