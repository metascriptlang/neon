import { registerNativeElement } from "./elements";
import { androidLibrary } from "../../../../ion/src/android";
import { niIndicatorCreate } from "./components.h";

when (ios) {
	@compile("../ios/activityIndicator.m", "-fobjc-arc");
} else when (android) {
	androidLibrary("../android/activityIndicator");
} else when (macos && !testBuild) {
	@compile("../macos/activityIndicator.m", "-fobjc-arc");
}

registerNativeElement("activityindicator", { create: (): Ptr<void> | null => niIndicatorCreate(), sizesItself: false });
