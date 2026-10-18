import { registerNativeElement } from "./elements";
import { androidLibrary } from "../../../../ion/src/android";
import { niWebViewCreate } from "./components.h";

when (ios) {
	@compile("../ios/webView.m", "-fobjc-arc");
	@passL("-framework WebKit");
} else when (android) {
	androidLibrary("../android/webView");
} else when (macos && !testBuild) {
	@compile("../macos/webView.m", "-fobjc-arc");
	@passL("-framework WebKit");
}

registerNativeElement("webview", { create: (): Ptr<void> | null => niWebViewCreate(), sizesItself: false });
