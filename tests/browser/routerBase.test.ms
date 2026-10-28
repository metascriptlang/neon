import { domHost } from "../../src/platform/browser/dom";
import { createBrowserRoutingHistory, followLinks } from "../../src/platform/browser/routingHistory";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { NeonNode } from "../../src/render/node";
import { A, NavigateOptions, RouterProvider, createRouter, createRoutes } from "../../src/navigation/router";
import { flush } from "../../src/core/runtime";

extern function js(code: cstring): string from "String((0, eval)(#))";

extern class HTMLElement {
	extern appendChild(child: HTMLElement): void;
	extern remove(): void;
}

extern class document {
	static body: HTMLElement;
	static extern createElement(tag: cstring): HTMLElement;
}

function Links(): NeonNode {
	return <nav>
		<A href="/docs/b">B</A>
		<a href="/outside">Outside</a>
		<a href="/application">Sibling</a>
	</nav>;
}

function Page(): NeonNode {
	return <p>page</p>;
}

test "a router under a base writes it to the address bar and follows only links under it" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/app/start", state: "" });
	const routes = createRoutes([
		{ path: "/start", component: Links },
		{ path: "/docs/b", component: Page },
		{ path: "/outside", component: Page },
	], "/app");
	const created = createRouter(routes, history);
	assert created.ok;
	if (!created.ok) { return; }
	const router = created.value;
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	const dispose = render(<RouterProvider router={router} />, domHost(), mount as unknown as HostNode);
	const stop = followLinks((url: string, options: NavigateOptions): boolean => router.navigate(url, options), router.base);
	js("window.__guard = e => { window.__prevented = e.defaultPrevented; e.preventDefault(); }; window.addEventListener('click', window.__guard, false); 1");
	const click = (href: string): string => {
		js("document.querySelector('a[href=\"" + href + "\"]').dispatchEvent(new MouseEvent('click', { bubbles: true, composed: true, cancelable: true })); 1");
		flush();
		return js("String(window.__prevented)");
	};
	try {
		assert js("document.querySelectorAll('a[href=\"/app/docs/b\"]').length") === "1", js("document.body.innerHTML");
		assert click("/outside") === "false";
		assert click("/application") === "false";
		assert history.read().url === "/app/start", history.read().url;
		assert click("/app/docs/b") === "true";
		assert history.read().url === "/app/docs/b", history.read().url;
		assert js("location.pathname") === "/app/docs/b", js("location.pathname");
	} finally {
		js("window.removeEventListener('click', window.__guard, false); 1");
		stop();
		dispose();
		router.dispose();
		mount.remove();
		history.replace(original);
	}
}
