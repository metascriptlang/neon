import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { domHost, documentBody } from "../../src/platform/browser/dom";
import { Svg, Rect } from "../../src/components/svg/elements";

render(element(<Svg width={10} height={10}><Rect x={0} y={0} width={10} height={10} /></Svg>), domHost(), documentBody());
