import { domHost } from "../../src/platform/browser/dom";
import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { el, text } from "../../src/render/node";
import { lazyModule } from "../../src/render/lazy";
import { lazy } from "../../src/macros/lazy";
import { Loading } from "../../src/macros/ui/flow";
import { flush } from "../../src/core/runtime";
import { sleepAsync } from "std/core/promise";
import { createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { LayoutProps, RouterProvider, createRouter, createRoutes } from "../../src/navigation/router";

extern function js(code: cstring): string from "String((0, eval)(#))";

extern class HTMLElement {
	extern appendChild(child: HTMLElement): void;
	extern remove(): void;
}

extern class document {
	static body: HTMLElement;
	static extern createElement(tag: cstring): HTMLElement;
}

async function loadPage(): Promise<(props: {}) => NeonNode> {
	const m = await import("./lazy/page");
	return m.Page;
}

const LazyPage = lazy<{}>(loadPage);

function Home(): NeonNode {
	return el("h1", [], [], text("home"));
}

function Shell(props: LayoutProps): NeonNode {
	return Loading({ children: props.children, fallback: el("b", [], [], text("loading")) });
}

function fetched(): boolean {
	return js("performance.getEntriesByType('resource').some(e => e.name.includes('/lazy/page'))") === "true";
}

test "a lazy route component fetches its module on the first navigation to it and renders it" {
	js("performance.setResourceTimingBufferSize(5000)");
	const routes = createRoutes([
		{ layout: Shell, children: [{ path: "/", component: Home }, { path: "/docs", component: LazyPage }] },
	]);
	const created = createRouter(routes, createMemoryRoutingHistory({ url: "/", state: "" }));
	assert created.ok;
	if (!created.ok) { return; }
	const router = created.value;
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	const dispose = render(<RouterProvider router={router} />, domHost(), mount as unknown as HostNode);
	try {
		assert js("document.body.innerText").indexOf("home") >= 0, js("document.body.innerText");
		assert !fetched(), "the page module was fetched before navigation";
		assert router.navigate("/docs");
		flush();
		let polls: int32 = 0;
		while (js("document.body.innerText").indexOf("fetched page") < 0 && polls < 500) { await sleepAsync(10); flush(); polls += 1; }
		assert js("document.body.innerText").indexOf("fetched page") >= 0, js("document.body.innerText");
		assert fetched(), "the page module was never fetched";
	} finally {
		dispose();
		router.dispose();
		mount.remove();
	}
}
