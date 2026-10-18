import { registerNativeElement } from "./elements";
import { niSvgCreate } from "./components.h";

registerNativeElement("svg", { create: (): Ptr<void> | null => niSvgCreate(), sizesItself: false });
