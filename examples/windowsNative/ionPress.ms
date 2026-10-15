// Pressables in an Ion window: hit-testing in child order, transforms, and the press, cancel and gesture phases.
//   msc build examples/windowsNative/ionPress.ms --output=out/windowsIonPress.exe
//   out/windowsIonPress.exe            opens the window and logs each press, pressIn and pressOut with its count

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/windows/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable } from "../../src/components/primitives";
import { niwStoredAccessibility } from "../../src/platform/windows/handoff.h";
import { exit } from "std/process";

const styles = createStyles({
	base: { width: 400, height: 260, backgroundColor: "#101820" },
	a: { position: "absolute", left: 20, top: 20, width: 140, height: 60, backgroundColor: "#e63a3a", justifyContent: "center", alignItems: "center" },
	b: { position: "absolute", left: 200, top: 20, width: 140, height: 60, backgroundColor: "#1c73d9" },
	cover: { position: "absolute", left: 270, top: 20, width: 70, height: 60, backgroundColor: "#7f8c8d" },
	c: { position: "absolute", left: 20, top: 120, width: 100, height: 100, backgroundColor: "#2ecc71", transform: "scale(0.5)" },
	d: { position: "absolute", left: 200, top: 120, width: 140, height: 60, backgroundColor: "#f1c40f" },
	e: { position: "absolute", left: 130, top: 150, width: 80, height: 20, backgroundColor: "#9b59b6", transform: "rotate(90deg)" },
	label: { color: "#ffffff", fontSize: 20 },
});

const [count, setCount] = createSignal(0);
let presses = 0;

function pressed(name: string): (e: NeonEvent) => void {
	return (e: NeonEvent): void => {
		presses += 1;
		console.log(`press ${name} ${presses} at ${e.x},${e.y}`);
		if (name === "A") { setCount(presses); }
	};
}

function note(what: string): (e: NeonEvent) => void {
	return (e: NeonEvent): void => { console.log(what); };
}

function App(): NeonNode {
	return <View style={styles.base}>
		<Pressable style={styles.a} accessibilityLabel="Press A" onPress={pressed("A")}>
			<Text style={styles.label}>{"A " + count()}</Text>
		</Pressable>
		<Pressable style={styles.b} onPress={pressed("B")} />
		<View style={styles.cover} />
		<Pressable style={styles.c} onPress={pressed("C")} />
		<Pressable style={styles.d} onPress={pressed("D")} onPressIn={note("in D")} onPressOut={note("out D")} />
		<Pressable style={styles.e} onPress={pressed("E")} />
	</View>;
}

exit(runNativeWindow(nativeWindowOptions("Neon press on Ion", 400, 260), App, (): void => {
	console.log(`stored label "Press A" on ${niwStoredAccessibility("accessibilityLabel", "Press A")} view, accessible "true" on ${niwStoredAccessibility("accessible", "true")} views`);
}));
