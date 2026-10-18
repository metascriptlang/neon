import { registerNativeElement } from "./elements";
import { niSvgCreate } from "./components.h";

when (ios) {
	@compile("../ios/svg.m", "-fobjc-arc");
}

registerNativeElement("svg", { create: (): Ptr<void> | null => niSvgCreate(), sizesItself: false });
