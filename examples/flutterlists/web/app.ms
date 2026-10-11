import { render } from "../../../src/render/host";
import { domHost, documentBody } from "../../../src/platform/browser/dom";
import { FlutterLists } from "../../components/flutterLists";

render(FlutterLists(), domHost(), documentBody());
