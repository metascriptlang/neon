import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { domHost, documentBody } from "../../src/platform/browser/dom";
import { View } from "../../src/components/primitives";

render(element(<View style={{ width: 10, height: 10 }} />), domHost(), documentBody());
