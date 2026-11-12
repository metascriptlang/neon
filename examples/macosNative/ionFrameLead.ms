// examples/voidFrames.ms on the macOS native host: 60 requestFrame callbacks in an Ion window with no Void, each
// reading its frame time against performance.now(). Exits 1 when the median lead is not inside one frame ahead, which
// is the case when the frame time is the moment the frame ran instead of its target presentation.
//   msc build examples/macosNative/ionFrameLead.ms --output=out/macosIonFrameLead && out/macosIonFrameLead

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createSignal } from "../../src/core/signal";
import { requestFrame } from "../../src/animation/frame";
import { NeonNode } from "../../src/render/node";
import { View, Text } from "../../src/components/primitives";
import { exit } from "std/process";

const FRAMES = 60;

function FrameLead(): NeonNode {
	const [n, setN] = createSignal<number>(0);
	const times: number[] = [];
	const leads: number[] = [];
	const tick = (time: number): void => {
		times.push(time);
		leads.push(time - performance.now());
		setN(times.length);
		if (times.length < FRAMES) {
			requestFrame(tick);
			return;
		}
		let most = 0.0;
		for (let i = 1; i < times.length; i += 1) {
			if (times[i] - times[i - 1] > most) { most = times[i] - times[i - 1]; }
		}
		leads.sort((a: number, b: number): number => a - b);
		const lead = leads[leads.length / 2];
		const ok = lead > 0 && lead <= most + 1;
		console.log(`${ok ? "ok  " : "FAIL"} lead median ${lead} min ${leads[0]} max ${leads[leads.length - 1]}, max gap ${most}`);
		exit(ok ? 0 : 1);
	};
	setTimeout((): void => { requestFrame(tick); }, 300);
	return <View style={{ flexGrow: 1, backgroundColor: "#101820" }}>
		<Text style={{ color: "#ffffff" }}>{`frame ${n()}`}</Text>
	</View>;
}

exit(runNativeWindow(nativeWindowOptions("Neon frame lead", 320, 120), FrameLead, null));
