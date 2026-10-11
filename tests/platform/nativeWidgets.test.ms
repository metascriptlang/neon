import { runApp } from "../../src/platform/native/host";
import { createSignal } from "../../src/core/signal";
import { View, Text } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { Collapsible } from "../../src/components/collapsible";
import { nmTeardown, nmLoop } from "./nativeBridgeMock.h";

// The UI loop for a while of wall time: timers, frames and the layout passes they batch.
function loopFor(ms: number): void {
	const end = performance.now() + ms;
	while (performance.now() < end) { nmLoop(); }
}

test "a closed Collapsible opens on the native host: its content reports a layout and the box grows" {
	const [collapsed, setCollapsed] = createSignal(true);
	let box = -1.0;
	let content = -1.0;
	const app = (): NeonNode => <View>
		<View onLayout={(e: NeonEvent): void => { box = e.height; }}>
			<Collapsible collapsed={collapsed()} duration={64}>
				<View style={{ height: 120 }} onLayout={(e: NeonEvent): void => { content = e.height; }}><Text>answer</Text></View>
			</Collapsible>
		</View>
	</View>;
	runApp(app);
	assert box === 0, "closed: " + box.toString();
	setCollapsed(false);
	loopFor(400);
	assert content === 120, "the content was laid out: " + content.toString();
	assert box === 120, "the box opened: " + box.toString();
	nmTeardown();
}

