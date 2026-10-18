import { registerNativeElement } from "./elements";
import { niWebViewCreate } from "./components.h";

registerNativeElement("webview", { create: (): Ptr<void> | null => niWebViewCreate(), sizesItself: false });
