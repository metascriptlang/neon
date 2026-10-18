import { registerNativeElement } from "./elements";
import { androidLibrary } from "../../../../ion/src/android";
import { niSwitchCreate } from "./components.h";

when (ios) {
	@compile("../ios/switch.m", "-fobjc-arc");
} else when (android) {
	androidLibrary("../android/switch");
} else when (macos && !testBuild) {
	@compile("../macos/switch.m", "-fobjc-arc");
}

registerNativeElement("switch", { create: (): Ptr<void> | null => niSwitchCreate(), sizesItself: true });
