import { registerNativeElement } from "./elements";
import { androidLibrary } from "../../../../ion/src/android";
import { niCameraCreate } from "./components.h";

when (ios) {
	@compile("../ios/camera.m", "-fobjc-arc");
	@passL("-framework AVFoundation");
} else when (android) {
	androidLibrary("../android/camera");
} else when (macos && !testBuild) {
	@compile("../macos/camera.m", "-fobjc-arc");
	@passL("-framework AVFoundation");
}

registerNativeElement("camera", { create: (): Ptr<void> | null => niCameraCreate(), sizesItself: false });
