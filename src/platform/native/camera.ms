import { registerNativeElement } from "./elements";
import { niCameraCreate } from "./components.h";

when (macos && !testBuild) {
	@compile("../macos/camera.m", "-fobjc-arc");
	@passL("-framework AVFoundation");
}

registerNativeElement("camera", { create: (): Ptr<void> | null => niCameraCreate(), sizesItself: false });
