import { domHost } from "../../src/platform/browser/dom";
import { createBrowserRoutingHistory } from "../../src/platform/browser/routingHistory";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { sleepAsync } from "std/core/promise";
import { RoutingSession } from "../../src/navigation/index";
import { createRoutingDemo, RoutingDemo } from "../../examples/components/routing";

extern function js(code: cstring): string from "String((0, eval)(#))";

extern class HTMLElement {
	extern appendChild(child: HTMLElement): void;
	extern remove(): void;
}

extern class document {
	static body: HTMLElement;
	static extern createElement(tag: cstring): HTMLElement;
}

function press(label: string): void {
	const clicked = js(`(() => {
		const element = document.querySelector('[aria-label="${label}"]');
		if (!element) return 'missing';
		element.click();
		return 'clicked';
	})()`);
	if (clicked !== "clicked") { throw new Error("missing routing button: " + label); }
}

test "custom navigation updates browser URLs and restores UI on browser back and forward" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/documents/home", state: "" });
	const demo = createRoutingDemo(history);
	assert demo.ok;
	if (demo.ok) {
		const model = demo.value;
		const mount = document.createElement("div");
		document.body.appendChild(mount);
		const dispose = render(
			<RoutingDemo model={model} />, domHost(), mount as unknown as HostNode,
		);
		try {
			press("Open document 42");
			assert history.read().url === "/documents/42";
			assert js("document.body.innerText").indexOf("Document 42") >= 0;
			press("Open inspector");
			assert history.read().url === "/documents/42?__nav.inspector=%2Fmaterials%2Fmetal";
			assert js("document.body.innerText").indexOf("Inspector metal") >= 0;
			assert history.go(-1);
			await sleepAsync(100);
			assert model.document() === "42" && model.inspector() === "";
			assert history.read().url === "/documents/42";
			assert history.go(1);
			await sleepAsync(100);
			assert model.inspector() === "metal";
			assert js("document.body.innerText").indexOf("Inspector metal") >= 0;
			model.session.dispose();
			assert history.go(-1);
			await sleepAsync(100);
			assert model.inspector() === "metal";
		} finally {
			model.dispose();
			dispose();
			mount.remove();
			history.replace(original);
		}
	}
}
