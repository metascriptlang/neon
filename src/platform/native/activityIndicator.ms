import { registerNativeElement } from "./elements";
import { niIndicatorCreate } from "./components.h";

registerNativeElement("activityindicator", { create: (): Ptr<void> | null => niIndicatorCreate(), sizesItself: false });
