import { registerNativeElement } from "./elements";
import { niModalCreate } from "./components.h";

registerNativeElement("modal", { create: (): Ptr<void> | null => niModalCreate(), sizesItself: false });
