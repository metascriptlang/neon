import { domHost } from "../../src/platform/browser/dom";
import { createBrowserRoutingHistory, followLinks } from "../../src/platform/browser/routingHistory";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { NeonNode } from "../../src/render/node";
import { A, NavigateOptions, RouterProvider, createRouter, createRoutes } from "../../src/navigation/router";
import { Scroller } from "../../src/navigation/scroll";
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
		<A href="/one">One</A>
		<A href="/two" replace>Two</A>
		<A href="/three" noScroll>Three</A>
		<A href="/four" target="_blank">Four</A>
		<A href="/five" target="_self">Five</A>
	</nav>;
}

function Page(): NeonNode {
	return <p>page</p>;
}

test "a link click honours replace and noScroll, and leaves target and modifier clicks to the browser" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/start", state: "" });
	const routes = createRoutes([
		{ path: "/start", component: Links },
		{ path: "/one", component: Page },
		{ path: "/two", component: Page },
		{ path: "/three", component: Page },
		{ path: "/four", component: Page },
		{ path: "/five", component: Page },
	]);
	const created = createRouter(routes, history);
	assert created.ok;
	if (!created.ok) { return; }
	const router = created.value;
	const arrivals: string[] = [];
	const scroller: Scroller = {
		arrived: (address: string, replace: boolean, scroll: boolean): void => {
			arrivals.push(address + " replace=" + replace.toString() + " scroll=" + scroll.toString());
		},
	};
	router.scrollWith(scroller);
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	const dispose = render(<RouterProvider router={router} />, domHost(), mount as unknown as HostNode);
	const stop = followLinks((url: string, options: NavigateOptions): boolean => router.navigate(url, options));
	js("window.__prevented = []; window.__guard = e => { window.__prevented.push(e.defaultPrevented); e.preventDefault(); }; window.addEventListener('click', window.__guard, false); 1");
	const click = (href: string, init: string): string => {
		const prevented = js("(() => { window.__prevented = []; document.querySelector('a[href=\"" + href + "\"]').dispatchEvent(new MouseEvent('click', { bubbles: true, composed: true, cancelable: true, " + init + " })); return window.__prevented.join(); })()");
		flush();
		return prevented;
	};
	const back = (): void => {
		history.replace({ url: "/start", state: "" });
		router.navigate("/start", { replace: true });
		flush();
		arrivals.length = 0;
	};
	try {
		const depth = history.index();
		assert click("/one", "") === "true";
		assert history.read().url === "/one" && history.index() === depth + 1, history.read().url;
		assert arrivals[arrivals.length - 1] === "/one replace=false scroll=true", arrivals.join(" | ");
		back();
		const kept = history.index();
		assert click("/two", "") === "true";
		assert history.read().url === "/two" && history.index() === kept, history.read().url + " " + history.index().toString();
		assert arrivals[arrivals.length - 1] === "/two replace=true scroll=true", arrivals.join(" | ");
		back();
		assert click("/three", "") === "true";
		assert arrivals[arrivals.length - 1] === "/three replace=false scroll=false", arrivals.join(" | ");
		back();
		assert click("/four", "") === "false";
		assert history.read().url === "/start", history.read().url;
		assert click("/five", "") === "false";
		assert history.read().url === "/start", history.read().url;
		assert click("/one", "ctrlKey: true") === "false";
		assert click("/one", "shiftKey: true") === "false";
		assert click("/one", "metaKey: true") === "false";
		assert click("/one", "altKey: true") === "false";
		assert click("/one", "button: 1") === "false";
		assert history.read().url === "/start", history.read().url;
	} finally {
		js("window.removeEventListener('click', window.__guard, false); 1");
		stop();
		dispose();
		router.dispose();
		mount.remove();
		history.replace(original);
	}
}
