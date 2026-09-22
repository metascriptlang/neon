@compile("./entry.m", "-fobjc-arc");

import { Counter } from "../components/counter";
import { render } from "../../src/render/host";
import { HostNode } from "../../src/render/host";
import { createIosHost, registerAndRun } from "../../src/platform/ios/host";

function mountApp(): void {
	const ios = createIosHost();
	render(Counter(), ios.host, ios.rootNode as HostNode);
	ios.relayout();
}

registerAndRun(mountApp);
