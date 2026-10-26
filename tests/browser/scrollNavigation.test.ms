import { domHost } from "../../src/platform/browser/dom";
import { createBrowserRoutingHistory } from "../../src/platform/browser/routingHistory";
import { followScroll } from "../../src/platform/browser/scroll";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { NeonNode, el, attr, text } from "../../src/render/node";
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

function tall(): NeonNode {
	return el("div", [attr("style", "height:3000px;position:relative")], [],
		el("div", [attr("id", "spot"), attr("style", "position:absolute;top:1500px")], [], text("spot")));
}

struct Open {
	router: Router;
	history: RoutingHistory;
	original: string;
	stop: Dispose;
	dispose: Dispose;
	mount: HTMLElement;
}

function open(start: string, navigationType: string = "navigate"): Open {
	const history = createBrowserRoutingHistory();
	const original = history.read().url;
	history.replace({ url: start, state: "" });
	const routes = createRoutes([
		{ path: "/a", component: tall },
		{ path: "/b", component: tall },
	]);
	const created = createRouter(routes, history);
	if (!created.ok) { throw new Error("router: " + created.error.toString()); }
	const router = created.value;
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	const dispose = render(<RouterProvider router={router} />, domHost(), mount as unknown as HostNode);
	const stop = followScroll(router, navigationType);
	return { router, history, original, stop, dispose, mount };
}

function close(app: Open): void {
	app.stop();
	app.dispose();
	app.router.dispose();
	app.mount.remove();
	app.history.replace({ url: app.original, state: "" });
	reach("scrollTo(0, 0)");
}

function scrolledTo(): number {
	return Number(reach("Math.round(scrollY)"));
}

function scrollTo(y: number): void {
	reach("scrollTo(0, " + y.toString() + ")");
}

async function settle(): Promise<void> {
	await sleepAsync(120);
}

test "a push to a new page scrolls to the top" {
	const app = open("/a");
	try {
		scrollTo(800);
		await settle();
		assert scrolledTo() === 800, "at " + scrolledTo().toString();
		assert app.router.navigate("/b");
		await settle();
		assert scrolledTo() === 0, "at " + scrolledTo().toString();
	} finally {
		close(app);
	}
}

test "a replace to a new page scrolls to the top" {
	const app = open("/a");
	try {
		scrollTo(800);
		await settle();
		assert app.router.navigate("/b", { replace: true });
		await settle();
		assert scrolledTo() === 0, "at " + scrolledTo().toString();
	} finally {
		close(app);
	}
}

test "a push to an address with a hash scrolls the target into view" {
	const app = open("/a");
	try {
		assert app.router.navigate("/b#spot");
		await settle();
		const top = Number(reach("Math.round(document.getElementById('spot').getBoundingClientRect().top)"));
		assert top === 0, "target top " + top.toString();
		assert scrolledTo() > 1000, "at " + scrolledTo().toString();
	} finally {
		close(app);
	}
}

test "a hash with no target scrolls to the top" {
	const app = open("/a");
	try {
		scrollTo(800);
		await settle();
		assert app.router.navigate("/b#missing");
		await settle();
		assert scrolledTo() === 0, "at " + scrolledTo().toString();
	} finally {
		close(app);
	}
}

test "a push with scroll false keeps the offset and still reaches a hash target" {
	const app = open("/a");
	try {
		scrollTo(800);
		await settle();
		assert app.router.navigate("/b", { scroll: false });
		await settle();
		assert scrolledTo() === 800, "kept " + scrolledTo().toString();
		assert app.router.navigate("/a#spot", { scroll: false });
		await settle();
		assert scrolledTo() > 1000, "hash target " + scrolledTo().toString();
	} finally {
		close(app);
	}
}

test "back and forward restore the offset of the entry they land on" {
	const app = open("/a");
	try {
		scrollTo(800);
		await settle();
		assert app.router.navigate("/b");
		await settle();
		scrollTo(300);
		await settle();
		assert app.history.go(-1);
		await settle();
		assert app.history.read().url === "/a", app.history.read().url;
		assert scrolledTo() === 800, "back " + scrolledTo().toString();
		assert app.history.go(1);
		await settle();
		assert app.history.read().url === "/b", app.history.read().url;
		assert scrolledTo() === 300, "forward " + scrolledTo().toString();
	} finally {
		close(app);
	}
}

test "a push drops the offsets of the entries it cuts off" {
	const app = open("/a");
	try {
		assert app.router.navigate("/b");
		await settle();
		scrollTo(900);
		await settle();
		assert app.history.go(-1);
		await settle();
		assert scrolledTo() === 0, "back to the start " + scrolledTo().toString();
		assert app.router.navigate("/b");
		await settle();
		assert app.history.go(-1);
		await settle();
		assert app.history.go(1);
		await settle();
		assert scrolledTo() === 0, "the new entry " + scrolledTo().toString();
	} finally {
		close(app);
	}
}

test "the page owns scroll restoration while a router follows it" {
	assert reach("history.scrollRestoration") === "auto", "before";
	const app = open("/a");
	try {
		assert reach("history.scrollRestoration") === "manual", "while followed";
	} finally {
		close(app);
	}
	assert reach("history.scrollRestoration") === "auto", "after";
}

test "a reloaded page restores the offset its entry left at pagehide" {
	const first = open("/a");
	scrollTo(700);
	await settle();
	reach("dispatchEvent(new Event('pagehide'))");
	close(first);
	scrollTo(0);
	const again = open("/a", "reload");
	try {
		assert scrolledTo() === 700, "reload " + scrolledTo().toString();
	} finally {
		close(again);
		reach("sessionStorage.clear()");
	}
}
