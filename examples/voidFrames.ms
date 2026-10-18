// An Ion window whose app paces itself with requestFrame: the callback runs once per Ion frame, before
// that frame draws, and an idle window asks for none. `--check` prints the measured gaps and exits.

import { element } from "../src/macros/ui/element";
import { NeonNode } from "../src/render/node";
import { createSignal } from "../src/core/signal";
import { requestFrame } from "../src/animation/frame";
import { Void, Text } from "../src/components/primitives";
import { runWindow, DesktopOptions, desktopOptions, frameCounts } from "../src/platform/ion/window";
import { exit } from "std/process";

const FRAMES = 60;

function App(): NeonNode {
	const [n, setN] = createSignal<number>(0);
	const times: number[] = [];
	const tick = (time: number): void => {
		times.push(time);
		setN(times.length);
		if (times.length < FRAMES) {
			requestFrame(tick);
			return;
		}
		let least = 1000000.0;
		let most = 0.0;
		for (let i = 1; i < times.length; i += 1) {
			const gap = times[i] - times[i - 1];
			if (gap < least) { least = gap; }
			if (gap > most) { most = gap; }
		}
		const mean = (times[times.length - 1] - times[0]) / (times.length - 1);
		const before = frameCounts();
		console.log(`frames ${times.length} gap mean ${mean} min ${least} max ${most} drawn ${before[1]}`);
		setTimeout((): void => {
			const after = frameCounts();
			console.log(`idle 500 ms: requested ${after[0] - before[0]} drawn ${after[1] - before[1]}`);
			exit(0);
		}, 500);
	};
	setTimeout((): void => { requestFrame(tick); }, 300);
	return element(
		<Void style={{ backgroundColor: "#1e1e2e", padding: 20 }}>
			<Text style={{ fontSize: 16, color: "#cdd6f4" }}>{`frame ${n()}`}</Text>
		</Void>
	);
}

const opts: DesktopOptions = { ...desktopOptions("Neon frames", 320, 120), font: "../void/assets/font.ttf" };
exit(runWindow(opts, App));
