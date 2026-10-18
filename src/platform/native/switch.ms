import { registerNativeElement } from "./elements";
import { niSwitchCreate } from "./components.h";

registerNativeElement("switch", { create: (): Ptr<void> | null => niSwitchCreate(), sizesItself: true });
