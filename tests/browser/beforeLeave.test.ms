import { domHost } from "../../src/platform/browser/dom";
import { createBrowserRoutingHistory } from "../../src/platform/browser/routingHistory";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { NeonNode } from "../../src/render/node";
import { BeforeLeaveEvent, RouterProvider, createRouter, createRoutes, useBeforeLeave } from "../../src/navigation/router";
import { flush } from "../../src/core/runtime";
import { sleepAsync } from "std/core/promise";

extern function js(code: cstring): string from "String((0, eval)(#))";

extern class HTMLElement {
	extern appendChild(child: HTMLElement): void;
	extern remove(): void;
}

extern class document {
	static body: HTMLElement;
	static extern createElement(tag: cstring): HTMLElement;
}

const asked: string[] = [];
let held: BeforeLeaveEvent | null = null;

function Form(): NeonNode {
	useBeforeLeave((e: BeforeLeaveEvent): void => {
		asked.push(typeof e.to === "string" ? e.to as string : "go " + (e.to as int32).toString());
		e.preventDefault();
		held = e;
	});
	return <p>form</p>;
}

function Page(): NeonNode {
	return <p>page</p>;
}

test "the browser back button is blocked by a before-leave listener and goes through with retry force" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/one", state: "" });
	const routes = createRoutes([
		{ path: "/one", component: Page },
		{ path: "/form", component: Form },
	]);
	const created = createRouter(routes, history);
	assert created.ok;
	if (!created.ok) { return; }
	const router = created.value;
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	const dispose = render(<RouterProvider router={router} />, domHost(), mount as unknown as HostNode);
	try {
		assert router.navigate("/form");
		flush();
		assert history.read().url === "/form", history.read().url;
		assert history.go(-1);
		await sleepAsync(150);
		assert asked.join(" | ") === "go -1", asked.join(" | ");
		assert js("location.pathname") === "/form", js("location.pathname");
		assert router.location().pathname === "/form", router.location().pathname;
		(held as BeforeLeaveEvent).retry(true);
		await sleepAsync(150);
		assert js("location.pathname") === "/one", js("location.pathname");
		assert router.location().pathname === "/one", router.location().pathname;
		assert asked.length === 1, asked.join(" | ");
	} finally {
		dispose();
		router.dispose();
		mount.remove();
		history.replace(original);
	}
}
