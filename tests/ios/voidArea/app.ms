import { createSignal } from "../../../src/core/signal";
import { NeonNode } from "../../../src/render/node";
import { NeonEvent } from "../../../src/render/event";
import { View, Text, Void } from "../../../src/components/primitives";
import { runApp } from "../../../src/platform/native/host";
import { setVoidAreaFont } from "../../../src/platform/native/voidArea";
import { resourcePath } from "../../../../ion/src/window";
import { join } from "std/fs/path";

function VoidAreaApp(): NeonNode {
	const [size, setSize] = createSignal("none");
	const [downs, setDowns] = createSignal(0);
	const [at, setAt] = createSignal("");
	return <View style={{ flexGrow: 1, backgroundColor: "#202020" }}>
		<View style={{ height: 160, justifyContent: "flex-end", padding: 12 }}>
			<Text style={{ color: "#ffffff", fontSize: 16 }}>{`void ${size()} downs ${downs()}${at()}`}</Text>
		</View>
		<Void style={{ flexGrow: 1 }}
			fallback={<View style={{ flexGrow: 1, backgroundColor: "#ff0000" }} />}>
			<View style={{ flexGrow: 1, backgroundColor: "#00ff00" }}
				onLayout={(e: NeonEvent): void => { setSize(`${e.width}x${e.height}`); }}
				onPointerDown={(e: NeonEvent): void => {
					setDowns(downs() + 1);
					setAt(` at ${Math.round(e.x)},${Math.round(e.y)}`);
				}}>
				<View style={{ width: 40, height: 40, backgroundColor: "#0000ff" }} />
			</View>
		</Void>
	</View>;
}

setVoidAreaFont({ font: join(resourcePath(), "assets/font.ttf"), fontFamily: null, fontBytes: null, defaultFontBytes: null });
runApp(VoidAreaApp);
