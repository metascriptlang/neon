import { registerNativeElement } from "./elements";
import { niVideoCreate } from "./components.h";

when (macos && !testBuild) {
	@compile("../macos/video.m", "-fobjc-arc");
	@passL("-framework AVFoundation");
	@passL("-framework AVKit");
	@passL("-framework CoreMedia");
}

registerNativeElement("video", { create: (): Ptr<void> | null => niVideoCreate(), sizesItself: false });
