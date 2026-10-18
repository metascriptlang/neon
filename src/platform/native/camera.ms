import { registerNativeElement } from "./elements";
import { niCameraCreate } from "./components.h";

registerNativeElement("camera", { create: (): Ptr<void> | null => niCameraCreate(), sizesItself: false });
