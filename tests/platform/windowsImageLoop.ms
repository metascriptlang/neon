import {
	runNativeWindow, nativeWindowOptions,
} from "../../src/platform/windows/ion";
import { closeWindow, onWake, Window } from "../../../ion/src/index";
import { View } from "../../src/components/primitives";
import { Image, ImageLoader } from "../../src/components/image";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { element } from "../../src/macros/ui/element";
import {
	imageLoopStart, imageLoopPictureUri, imageLoopOnWake,
	imageLoopOnReport, imageLoopFinish,
} from "./windowsImageLoop.h";
import { exit } from "std/process";

when (windows) {
	@compile("./windowsImageLoop.cpp");
	@passL("-lws2_32");
}

const metadata = imageLoopStart() as string;
const picture = imageLoopPictureUri() as string;
let win: Window | null = null;
let metadataSeen = false;
let pictureSeen = false;
let failed = false;
let watchdog: number = 0;

function finishIfReady(): void {
	if (!metadataSeen || !pictureSeen) { return; }
	clearTimeout(watchdog);
	setTimeout((): void => {
		if (win !== null) { closeWindow(win as Window); }
	}, 0);
}

function App(): NeonNode {
	return element(<View style={{ width: 120, height: 120 }}>
		<Image
			style={{ width: 100, height: 100 }}
			source={{ uri: picture }}
			onLoad={(e: NeonEvent): void => {
				imageLoopOnReport();
				console.log(`image-loop picture ${e.width}x${e.height}`);
				if (pictureSeen || e.width !== 4 || e.height !== 4) {
					failed = true;
				}
				pictureSeen = true;
				finishIfReady();
			}}
			onError={(e: NeonEvent): void => {
				console.log(`image-loop picture error: ${e.value}`);
				failed = true;
				pictureSeen = true;
				finishIfReady();
			}}
		/>
	</View>);
}

const result = runNativeWindow(
	nativeWindowOptions("Neon image loop ownership pin", 120, 120),
	App,
	(window: Window): void => {
		win = window;
		onWake((): void => { imageLoopOnWake(); });
		watchdog = setTimeout((): void => {
			console.log("image-loop watchdog: real delivery did not complete");
			failed = true;
			closeWindow(window);
		}, 5000);
		ImageLoader.getSize(metadata, (w: number, h: number): void => {
			imageLoopOnReport();
			console.log(`image-loop metadata ${w}x${h}`);
			if (metadataSeen || w !== 4 || h !== 2) { failed = true; }
			metadataSeen = true;
			finishIfReady();
		}, (error: Error): void => {
			console.log(`image-loop metadata error: ${error.message}`);
			failed = true;
			metadataSeen = true;
			finishIfReady();
		});
	},
);
clearTimeout(watchdog);
if (result !== 0 || failed || !metadataSeen || !pictureSeen) { exit(1); }
exit(imageLoopFinish());
