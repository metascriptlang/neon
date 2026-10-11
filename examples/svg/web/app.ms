import { render } from "../../../src/render/host";
import { domHost, documentBody } from "../../../src/platform/browser/dom";
import { SvgGallery } from "../../components/svgGallery";

render(SvgGallery(), domHost(), documentBody());
