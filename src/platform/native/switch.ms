import { registerNativeElement } from "./elements";
import { niSwitchCreate } from "./components.h";

when (macos && !testBuild) {
	@compile("../macos/switch.m", "-fobjc-arc");
}

registerNativeElement("switch", { create: (): Ptr<void> | null => niSwitchCreate(), sizesItself: true });
