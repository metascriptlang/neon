import { registerNativeElement } from "./elements";
import { niModalCreate } from "./components.h";

when (macos && !testBuild) {
	@compile("../macos/modal.m", "-fobjc-arc");
}

registerNativeElement("modal", { create: (): Ptr<void> | null => niModalCreate(), sizesItself: false });
