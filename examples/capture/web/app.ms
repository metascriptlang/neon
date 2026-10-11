import { render } from "../../../src/render/host";
import { domHost, documentBody } from "../../../src/platform/browser/dom";
import { CaptureApp } from "../capture";

render(CaptureApp(), domHost(), documentBody());
