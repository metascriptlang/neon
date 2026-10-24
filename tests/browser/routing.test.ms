import { domHost } from "../../src/platform/browser/dom";
import { createBrowserRoutingHistory, followLinks } from "../../src/platform/browser/routingHistory";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { sleepAsync } from "std/core/promise";
import { NeonNode } from "../../src/render/node";
import { Text } from "../../src/components/primitives";
import {
	LinkingOptions,
	NavigationContainer,
	NavigationContainerRef,
	NavigationEventArg,
	RoutingError,
	RoutingRegistry,
	RoutingSession,
	ScreenProps,
	createDrawerNavigator,
	createNavigationContainerRef,
	createRoutingSession,
	createStackNavigator,
} from "../../src/navigation/index";
import { createRoot } from "../../src/core/owner";
import { flush } from "../../src/core/runtime";
import { Dispose } from "../../src/core/types";
import { PreloadArgs } from "../../src/navigation/route";
import { A, RouterProvider, createRouter, createRoutes } from "../../src/navigation/router";
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

interface ItemParams {
	id: string;
}

const Store = createStackNavigator<ItemParams>();

const storeLinking: LinkingOptions = {
	prefixes: [],
	enabled: false,
	config: {
		screens: [
			{ name: "Catalog", path: "store" },
			{ name: "Product", path: "store/product/:id" },
		],
	},
};

function Catalog(props: ScreenProps<ItemParams>): NeonNode {
	return <Text>Catalog page</Text>;
}

let guarded = false;

function Product(props: ScreenProps<ItemParams>): NeonNode {
	const params = props.route.params;
	if (guarded) {
		props.navigation.addListener("beforeRemove", (e: NavigationEventArg): void => {
			e.preventDefault();
		});
	}
	return <Text>{"Product " + (params() === null ? "-" : (params() as ItemParams).id)}</Text>;
}

function parseItem(values: Map<string, string>): ItemParams {
	return { id: values.get("id") ?? "" };
}

function stringifyItem(params: ItemParams): Map<string, string> {
	const values = new Map<string, string>();
	values.set("id", params.id);
	return values;
}

test "a built-in stack follows browser back and forward through the routing registry" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/store", state: "" });
	const registry = new RoutingRegistry("main");
	const ref = createNavigationContainerRef();
	const errors: RoutingError[] = [];
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	let opened: RoutingSession | null = null;
	const dispose = createRoot((stop: Dispose): Dispose => {
		const app = NavigationContainer({
			children: <Store.Navigator>
				<Store.Screen name="Catalog" component={Catalog} />
				<Store.Screen name="Product" component={Product}
					parseParams={parseItem} stringifyParams={stringifyItem} />
			</Store.Navigator>,
			linking: storeLinking,
			ref,
			routing: { registry, scope: "main" },
		});
		const created = createRoutingSession(registry, history, (failure: RoutingError): void => {
			errors.push(failure);
		});
		if (created.ok) { opened = created.value; }
		app(domHost(), mount as unknown as HostNode, null);
		return stop;
	});
	assert opened !== null;
	if (opened !== null) {
		const session = opened as RoutingSession;
		try {
			assert js("document.body.innerText").indexOf("Catalog page") >= 0;
			assert session.navigate("/store/product/42", false).ok;
			assert history.read().url === "/store/product/42";
			assert js("document.body.innerText").indexOf("Product 42") >= 0;
			assert session.navigate("/store/product/7", false).ok;
			assert history.go(-1);
			await sleepAsync(100);
			assert ref.currentPath() === "Product", ref.currentPath();
			assert js("document.body.innerText").indexOf("Product 42") >= 0;
			assert history.go(-1);
			await sleepAsync(100);
			assert ref.currentPath() === "Catalog", ref.currentPath();
			assert history.read().url === "/store";
			assert history.go(2);
			await sleepAsync(100);
			assert js("document.body.innerText").indexOf("Product 7") >= 0;
			assert errors.length === 0;
		} finally {
			session.dispose();
			dispose();
			mount.remove();
			history.replace(original);
		}
	}
}

test "a built-in stack on browser history records in-app navigation and follows back and forward" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/store", state: "" });
	const registry = new RoutingRegistry("main");
	const ref = createNavigationContainerRef();
	const errors: RoutingError[] = [];
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	let opened: RoutingSession | null = null;
	const dispose = createRoot((stop: Dispose): Dispose => {
		const app = NavigationContainer({
			children: <Store.Navigator>
				<Store.Screen name="Catalog" component={Catalog} />
				<Store.Screen name="Product" component={Product}
					parseParams={parseItem} stringifyParams={stringifyItem} />
			</Store.Navigator>,
			linking: storeLinking,
			ref,
			routing: { registry, scope: "main" },
		});
		const created = createRoutingSession(registry, history, (failure: RoutingError): void => {
			errors.push(failure);
		});
		if (created.ok) { opened = created.value; }
		app(domHost(), mount as unknown as HostNode, null);
		return stop;
	});
	assert opened !== null;
	if (opened !== null) {
		const session = opened as RoutingSession;
		const stop = ref.enableHistory(session);
		try {
			assert history.read().url === "/store", history.read().url;
			const start = session.index();
			assert ref.linkTo("/store/product/42");
			assert history.read().url === "/store/product/42", history.read().url;
			assert session.index() === start + 1, session.index().toString();
			assert js("document.body.innerText").indexOf("Product 42") >= 0;
			ref.goBack();
			await sleepAsync(100);
			assert history.read().url === "/store", history.read().url;
			assert session.index() === start, session.index().toString();
			assert history.go(1);
			await sleepAsync(100);
			assert ref.currentPath() === "Product", ref.currentPath();
			assert js("document.body.innerText").indexOf("Product 42") >= 0;
			assert history.go(-1);
			await sleepAsync(100);
			assert ref.currentPath() === "Catalog", ref.currentPath();
			assert history.read().url === "/store", history.read().url;
			assert errors.length === 0, errors.length.toString();
		} finally {
			stop();
			session.dispose();
			dispose();
			mount.remove();
			history.replace(original);
		}
	}
}

interface Mounted {
	session: RoutingSession;
	errors: RoutingError[];
	stop: Dispose;
	dispose: Dispose;
}

function mountOnBrowser(
	content: NeonNode,
	options: LinkingOptions,
	ref: NavigationContainerRef,
	mount: HTMLElement,
): Mounted {
	const history = createBrowserRoutingHistory();
	const registry = new RoutingRegistry("main");
	const errors: RoutingError[] = [];
	let opened: RoutingSession | null = null;
	const dispose = createRoot((stop: Dispose): Dispose => {
		const app = NavigationContainer({
			children: content,
			linking: options,
			ref,
			routing: { registry, scope: "main" },
		});
		const created = createRoutingSession(registry, history, (failure: RoutingError): void => {
			errors.push(failure);
		});
		if (!created.ok) { throw new Error("session: " + created.error.toString()); }
		opened = created.value;
		app(domHost(), mount as unknown as HostNode, null);
		return stop;
	});
	const session = opened as RoutingSession;
	return { session, errors, stop: ref.enableHistory(session), dispose };
}

function unmount(app: Mounted, mount: HTMLElement): void {
	app.stop();
	app.session.dispose();
	app.dispose();
	mount.remove();
}

test "browser back stays on a stack screen whose beforeRemove prevents it" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/store", state: "" });
	const ref = createNavigationContainerRef();
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	guarded = true;
	const app = mountOnBrowser(<Store.Navigator>
		<Store.Screen name="Catalog" component={Catalog} />
		<Store.Screen name="Product" component={Product}
			parseParams={parseItem} stringifyParams={stringifyItem} />
	</Store.Navigator>, storeLinking, ref, mount);
	try {
		assert ref.linkTo("/store/product/42");
		const at = app.session.index();
		assert history.go(-1);
		await sleepAsync(200);
		assert ref.currentPath() === "Product", ref.currentPath();
		assert history.read().url === "/store/product/42", history.read().url;
		assert app.session.index() === at, app.session.index().toString();
		assert js("document.body.innerText").indexOf("Product 42") >= 0;
		assert app.errors.length === 0, app.errors.length.toString();
	} finally {
		guarded = false;
		unmount(app, mount);
		history.replace(original);
	}
}

const Side = createDrawerNavigator<string>();

const sideLinking: LinkingOptions = {
	prefixes: [],
	enabled: false,
	config: { screens: [{ name: "One", path: "one" }, { name: "Two", path: "two" }] },
};

function Page(props: ScreenProps<string>): NeonNode {
	return <Text>{"Page " + props.route.name}</Text>;
}

function drawerShown(): boolean {
	return js("String(!!document.querySelector('[aria-label=\"Close navigation menu\"]'))") ===
		"true";
}

test "opening a drawer adds a browser entry that browser back closes" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/one", state: "" });
	const ref = createNavigationContainerRef();
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	const app = mountOnBrowser(<Side.Navigator>
		<Side.Screen name="One" component={Page} />
		<Side.Screen name="Two" component={Page} />
	</Side.Navigator>, sideLinking, ref, mount);
	try {
		const start = app.session.index();
		ref.openDrawer();
		flush();
		assert app.session.index() === start + 1, app.session.index().toString();
		assert history.read().url === "/one", history.read().url;
		await sleepAsync(400);
		assert drawerShown(), "the drawer opened";
		assert history.go(-1);
		await sleepAsync(400);
		assert !drawerShown(), "browser back closed the drawer";
		assert app.session.index() === start, app.session.index().toString();
		assert history.go(1);
		await sleepAsync(400);
		assert drawerShown(), "browser forward opened it again";
		ref.closeDrawer();
		flush();
		await sleepAsync(400);
		assert app.session.index() === start, app.session.index().toString();
		assert history.read().url === "/one", history.read().url;
		assert app.errors.length === 0, app.errors.length.toString();
	} finally {
		unmount(app, mount);
		history.replace(original);
	}
}

const preloads: string[] = [];

function PreloadedPage(): NeonNode {
	preloads.push("render");
	return <p>page</p>;
}

function Links(props: { children: NeonNode }): NeonNode {
	return <nav><A href="/docs/b">B</A>{props.children}</nav>;
}

function noteDoc(args: PreloadArgs<Map<string, string>>): void {
	preloads.push((args.params.get("slug") ?? "") + " " + args.intent);
}

test "a router in Chrome preloads as initial at open, navigate on a link click and native on browser back" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/docs/a", state: "" });
	const routes = createRoutes([
		{ layout: Links, children: [{ path: "/docs/:slug", component: PreloadedPage, preload: noteDoc }] },
	]);
	const created = createRouter(routes, history);
	assert created.ok;
	if (!created.ok) { return; }
	const router = created.value;
	const mount = document.createElement("div");
	document.body.appendChild(mount);
	preloads.length = 0;
	const dispose = render(<RouterProvider router={router} />, domHost(), mount as unknown as HostNode);
	const stop = followLinks((url: string): boolean => router.navigate(url));
	try {
		assert preloads.join(" | ") === "a initial | render", preloads.join(" | ");
		preloads.length = 0;
		js("document.querySelector('a[href=\"/docs/b\"]').click()");
		flush();
		assert history.read().url === "/docs/b", history.read().url;
		assert preloads.join(" | ") === "b navigate | render", preloads.join(" | ");
		preloads.length = 0;
		assert history.go(-1);
		await sleepAsync(100);
		assert history.read().url === "/docs/a", history.read().url;
		assert preloads.join(" | ") === "a native | render", preloads.join(" | ");
	} finally {
		stop();
		dispose();
		router.dispose();
		mount.remove();
		history.replace(original);
	}
}
