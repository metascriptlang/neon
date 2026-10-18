import { registerNativeElement } from "./elements";
import { niIndicatorCreate } from "./components.h";

when (ios) {
	@compile("../ios/activityIndicator.m", "-fobjc-arc");
} else when (macos && !testBuild) {
	@compile("../macos/activityIndicator.m", "-fobjc-arc");
}

registerNativeElement("activityindicator", { create: (): Ptr<void> | null => niIndicatorCreate(), sizesItself: false });
