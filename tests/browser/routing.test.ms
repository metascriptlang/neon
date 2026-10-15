import { domHost } from "../../src/platform/browser/dom";
import { createBrowserRoutingHistory } from "../../src/platform/browser/routingHistory";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { sleepAsync } from "std/core/promise";
import { NeonNode } from "../../src/render/node";
import { Text } from "../../src/components/primitives";
import {
	LinkingOptions,
	NavigationContainer,
	RoutingError,
	RoutingRegistry,
	RoutingSession,
	ScreenProps,
	createNavigationContainerRef,
	createRoutingSession,
	createStackNavigator,
} from "../../src/navigation/index";
import { createRoot } from "../../src/core/owner";
import { Dispose } from "../../src/core/types";
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

function Product(props: ScreenProps<ItemParams>): NeonNode {
	const params = props.route.params;
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
