import { registerNativeElement } from "./elements";
import { androidLibrary } from "../../../../ion/src/android";
import { niSvgCreate } from "./components.h";

when (ios) {
	@compile("../ios/svg.m", "-fobjc-arc");
} else when (android) {
	androidLibrary("../android/svg");
} else when (macos && !testBuild) {
	@compile("../macos/svg.m", "-fobjc-arc");
}

registerNativeElement("svg", { create: (): Ptr<void> | null => niSvgCreate(), sizesItself: false });
