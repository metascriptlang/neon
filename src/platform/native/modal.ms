import { registerNativeElement } from "./elements";
import { androidLibrary } from "../../../../ion/src/android";
import { niModalCreate } from "./components.h";

when (ios) {
	@compile("../ios/modal.m", "-fobjc-arc");
} else when (android) {
	androidLibrary("../android/modal");
} else when (macos && !testBuild) {
	@compile("../macos/modal.m", "-fobjc-arc");
}

registerNativeElement("modal", { create: (): Ptr<void> | null => niModalCreate(), sizesItself: false });
