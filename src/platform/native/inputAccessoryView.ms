import { registerNativeElement } from "./elements";
import { niInputAccessoryViewCreate } from "./components.h";

when (ios) {
	@compile("../ios/inputAccessoryView.m", "-fobjc-arc");
}

registerNativeElement("inputaccessoryview", { create: (): Ptr<void> | null => niInputAccessoryViewCreate(), sizesItself: false });
