import { registerNativeElement } from "./elements";
import { niVideoCreate } from "./components.h";

registerNativeElement("video", { create: (): Ptr<void> | null => niVideoCreate(), sizesItself: false });
