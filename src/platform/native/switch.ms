import { registerNativeElement } from "./elements";
import { niSwitchCreate } from "./components.h";

when (ios) {
	@compile("../ios/switch.m", "-fobjc-arc");
} else when (macos && !testBuild) {
	@compile("../macos/switch.m", "-fobjc-arc");
}

registerNativeElement("switch", { create: (): Ptr<void> | null => niSwitchCreate(), sizesItself: true });
