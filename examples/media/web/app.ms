import { render } from "../../../src/render/host";
import { domHost, documentBody } from "../../../src/platform/browser/dom";
import { MediaApp } from "../media";

render(MediaApp(), domHost(), documentBody());
