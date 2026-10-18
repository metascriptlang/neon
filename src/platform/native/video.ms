import { registerNativeElement } from "./elements";
import { androidLibrary } from "../../../../ion/src/android";
import { niVideoCreate } from "./components.h";

when (ios) {
	@compile("../ios/video.m", "-fobjc-arc");
	@passL("-framework AVFoundation");
	@passL("-framework AVKit");
	@passL("-framework CoreMedia");
} else when (android) {
	androidLibrary("../android/video");
} else when (macos && !testBuild) {
	@compile("../macos/video.m", "-fobjc-arc");
	@passL("-framework AVFoundation");
	@passL("-framework AVKit");
	@passL("-framework CoreMedia");
}

registerNativeElement("video", { create: (): Ptr<void> | null => niVideoCreate(), sizesItself: false });
