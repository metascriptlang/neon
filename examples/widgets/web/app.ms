import { render } from "../../../src/render/host";
import { domHost, documentBody } from "../../../src/platform/browser/dom";
import { Widgets } from "../../components/widgets";

render(Widgets(), domHost(), documentBody());
