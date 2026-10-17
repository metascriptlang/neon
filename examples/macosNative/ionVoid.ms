// examples/voidWindow.ms on macOS: a counter and a text field inside one full-window <Void> of an Ion window,
// Void's CAMetalLayer under Ion's content view, pointer and keys through Ion's records.
//   msc build examples/macosNative/ionVoid.ms --output=out/macosIonVoid
//   out/macosIonVoid            (run from the neon checkout: the font path is relative)
//   out/macosIonVoid --check    clicks +1 three times, types "hi" and Return through AppKit events, exits 0 when the state follows

import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { Void, View, Text, TextInput, Pressable } from "../../src/components/primitives";
import { runWindow, DesktopOptions, desktopOptions } from "../../src/platform/ion/window";
import { harnessIsCheck, harnessClick, harnessPostKeys } from "./harness.h";
import { exit } from "std/process";

when (macos) {
	@compile("./harness.m", "-fobjc-arc");
}

const title = "Neon in a Void on macOS";

function App(): NeonNode {
	const [count, setCount] = createSignal(0);
	const [name, setName] = createSignal("");
	const [submitted, setSubmitted] = createSignal("");
	if (harnessIsCheck() !== 0) {
		setTimeout((): void => { harnessClick(title, 80, 74); }, 500);
		setTimeout((): void => { harnessClick(title, 80, 74); }, 700);
		setTimeout((): void => { harnessClick(title, 80, 74); }, 900);
		setTimeout((): void => { harnessClick(title, 200, 122); }, 1100);
		setTimeout((): void => { harnessPostKeys(title, "hi\n"); }, 1300);
		setTimeout((): void => {
			const ok = count() === 3 && name() === "hi" && submitted() === "hi";
			console.log(`${ok ? "ok  " : "FAIL"} count=${count()} text="${name()}" submitted="${submitted()}", want 3, "hi", "hi"`);
			exit(ok ? 0 : 1);
		}, 2000);
	}
	return element(
		<Void style={{ backgroundColor: "#1e1e2e", padding: 24 }}>
			<View style={{ height: 32 }}>
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
			}} onSubmitEditing={(e: NeonEvent): void => {
				setSubmitted(e.value);
				console.log("submit \"" + e.value + "\"");
			}} />
			<View style={{ height: 32 }}>
				<Text style={{ color: "#a6e3a1" }}>Hello, {name()}</Text>
			</View>
		</Void>
	);
}

const opts: DesktopOptions = { ...desktopOptions(title, 640, 360), font: "../void/assets/font.ttf" };
exit(runWindow(opts, App));
