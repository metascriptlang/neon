import { registerNativeElement } from "./elements";
import { niWebViewCreate } from "./components.h";

when (macos && !testBuild) {
	@compile("../macos/webView.m", "-fobjc-arc");
	@passL("-framework WebKit");
}

registerNativeElement("webview", { create: (): Ptr<void> | null => niWebViewCreate(), sizesItself: false });
