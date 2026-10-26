import { domHost } from "../../src/platform/browser/dom";
import { createBrowserRoutingHistory } from "../../src/platform/browser/routingHistory";
import { followAnnouncements } from "../../src/platform/browser/announce";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { NeonNode, el, text } from "../../src/render/node";
import { RoutingHistory } from "../../src/navigation/routingHistory";
import { Router, RouterProvider, createRouter, createRoutes } from "../../src/navigation/router";
import { Dispose } from "../../src/core/types";
import { sleepAsync } from "std/core/promise";

extern function reach(code: cstring): string from "String((0, eval)(#))";

extern class HTMLElement {
	extern appendChild(child: HTMLElement): void;
	extern remove(): void;
}

extern class document {
	static body: HTMLElement;
	static extern createElement(tag: cstring): HTMLElement;
}

function first(): NeonNode {
	reach("document.title = 'First page'");
	return el("p", [], [], text("first"));
}

function second(): NeonNode {
	reach("document.title = 'Second page'");
	return el("p", [], [], text("second"));
}

function headed(): NeonNode {
	reach("document.title = ''");
	return el("h1", [], [], text("Heading only"));
}

struct Open {
	router: Router;
	history: RoutingHistory;
	original: string;
	stop: Dispose;
	dispose: Dispose;
	mount: HTMLElement;
}

function open(): Open {
	const history = createBrowserRoutingHistory();
	const original = history.read().url;
	history.replace({ url: "/first", state: "" });
	const routes = createRoutes([
		{ path: "/first", component: first },
		{ path: "/second", component: second },
		{ path: "/headed", component: headed },
	]);
	const created = createRouter(routes, history);
	if (!created.ok) { throw new Error("router: " + created.error.toString()); }
	const router = created.value;
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	const dispose = render(<RouterProvider router={router} />, domHost(), mount as unknown as HostNode);
	const stop = followAnnouncements(router);
	return { router, history, original, stop, dispose, mount };
}

function close(app: Open): void {
	app.stop();
	app.dispose();
	app.router.dispose();
	app.mount.remove();
	app.history.replace({ url: app.original, state: "" });
}

function announced(): string {
	return reach("document.getElementById('__neon-route-announcer__')?.textContent ?? 'none'");
}

test "a client navigation announces the new page title in an assertive alert region and the first load does not" {
	const app = open();
	try {
		await sleepAsync(50);
		assert announced() === "", "first load: " + announced();
		assert reach("document.getElementById('__neon-route-announcer__').getAttribute('role')") === "alert";
		assert reach("document.getElementById('__neon-route-announcer__').getAttribute('aria-live')") === "assertive";
		assert app.router.navigate("/second");
		await sleepAsync(50);
		assert announced() === "Second page", announced();
		assert app.history.go(-1);
		await sleepAsync(100);
		assert announced() === "First page", "back: " + announced();
	} finally {
		close(app);
	}
}

test "a page with no title is announced by its first heading" {
	const app = open();
	try {
		await sleepAsync(50);
		const others = reach("[...document.querySelectorAll('h1')].map(h => h.outerHTML).join('|')");
		assert others === "", others;
		assert app.router.navigate("/headed");
		await sleepAsync(50);
		assert announced() === "Heading only", announced();
	} finally {
		close(app);
	}
}

test "disposing the announcer removes its region" {
	const app = open();
	close(app);
	assert announced() === "none", announced();
}
