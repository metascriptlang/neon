// A counter and a text field inside one full-window <Void> of an Ion window.
//   msc build examples/voidWindow.ms --output=out/voidWindow.exe
//   cp ../ion/vendor/webview2/runtime/x64/WebView2Loader.dll out/
//   out/voidWindow.exe            (run from the neon checkout: the font path is relative)

import { createSignal } from "../src/core/signal";
import { element } from "../src/macros/ui/element";
import { NeonNode } from "../src/render/node";
import { NeonEvent } from "../src/render/event";
import { Void, View, Text, TextInput, Pressable } from "../src/components/primitives";
import { runWindow, DesktopOptions, desktopOptions } from "../src/platform/ion/window";
import { exit } from "std/process";

function App(): NeonNode {
	const [count, setCount] = createSignal(0);
	const [name, setName] = createSignal("");
	return element(
		<Void style={{ backgroundColor: "#1e1e2e", padding: 24 }}>
			<View style={{ height: 32 }} onLayout={(e: NeonEvent): void => { console.log("layout header " + e.width.toString() + "x" + e.height.toString()); }}>
				<Text style={{ fontSize: 20, color: "#cdd6f4" }}>Count: {count().toString()}</Text>
			</View>
			<Pressable style={{ width: 120, height: 36, backgroundColor: "#89b4fa" }} onPress={(): void => {
				setCount(count() + 1);
				console.log("press count=" + count().toString());
			}}>
				<Text style={{ color: "#11111b" }}>+1</Text>
			</Pressable>
			<View style={{ height: 16 }} />
			<TextInput style={{ height: 28, backgroundColor: "#313244", color: "#cdd6f4" }} value={name()} onChangeText={(t: string): void => {
				setName(t);
				console.log("changetext \"" + t + "\"");
			}} onSubmitEditing={(e: NeonEvent): void => { console.log("submit \"" + e.value + "\""); }} />
			<View style={{ height: 32 }}>
				<Text style={{ color: "#a6e3a1" }}>Hello, {name()}</Text>
			</View>
		</Void>
	);
}

const opts: DesktopOptions = { ...desktopOptions("Neon in a Void", 640, 360), font: "../void/assets/font.ttf" };
exit(runWindow(opts, App));
