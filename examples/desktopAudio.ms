// expo-av's Audio.Sound in an Ion window: plays the capture chime, logs its progress and its end,
// then exits 0 once didJustFinish arrived, 1 on any failure.
//   msc build examples/desktopAudio.ms --output=out/desktopAudio.exe
//   out/desktopAudio.exe          (run from the neon checkout: the asset paths are relative)

import { element } from "../src/macros/ui/element";
import { NeonNode } from "../src/render/node";
import { Void, View } from "../src/components/primitives";
import { Audio, AVPlaybackStatus } from "../src/api/audio";
import { runWindow, DesktopOptions, desktopOptions } from "../src/platform/ion/window";
import { exit } from "std/process";

const CHIME = "examples/capture/assets/chime.wav";

let progress = 0;

function onStatus(status: AVPlaybackStatus): void {
	if (status.didJustFinish) {
		console.log(`finished at ${status.positionMillis} of ${status.durationMillis} ms after ${progress} progress updates`);
		exit(progress > 0 ? 0 : 1);
	}
	if (status.isPlaying) { progress += 1; }
}

async function play(): Promise<void> {
	try {
		const made = await Audio.Sound.createAsync({ uri: CHIME }, { shouldPlay: true, progressUpdateIntervalMillis: 50 }, onStatus);
		console.log(`loaded ${made.status.durationMillis} ms, playing=${made.status.isPlaying}`);
	} catch (e) {
		console.log(`desktopAudio: ${e.message}`);
		exit(1);
	}
}

function App(): NeonNode {
	play();
	return element(<Void style={{ backgroundColor: "#1e1e2e" }}><View style={{ flexGrow: 1 }} /></Void>);
}

const opts: DesktopOptions = { ...desktopOptions("Neon audio", 320, 160), font: "../void/assets/font.ttf" };
exit(runWindow(opts, App));
