import { Dispose } from "../../src/core/types";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import { Linking, publishUrl } from "../../src/api/linking";
import {
	LinkingConfig,
	LinkingOptions,
	NavTarget,
	NavigationContainer,
	NavigationRoute,
	NavigationState,
	ScreenProps,
	createNavigationContainerRef,
	createStackNavigator,
	decodeComponent,
	pathFromState,
	pathOf,
	targetFromPath,
	targetFromURL,
	useRoute,
} from "../../src/navigation/index";
import { FakeServices } from "../api/fakeServices";
import { visibleText } from "./navHarness";

const config: LinkingConfig = {
	screens: [
		{
			name: "Shop",
			path: "shop",
			screens: [
				{ name: "Product", path: "product/:id" },
				{ name: "Reviews", path: "product/:id/reviews/:page?" },
				{ name: "Catalog", path: "" },
			],
		},
		{ name: "Profile", path: "user/:name", exact: true },
		{ name: "Missing", path: "*" },
	],
};

function describe(target: NavTarget | null): string {
	let out = "";
	let current = target;
	while (current !== null) {
		const here = current as NavTarget;
		let part = here.name;
		const values = here.values;
		if (values !== null) {
			const keys: string[] = [];
			for (const key of values as Map<string, string>) { keys.push(key); }
			keys.sort();
			const pairs: string[] = [];
			for (const key of keys) { pairs.push(key + "=" + ((values as Map<string, string>).get(key) ?? "")); }
			part += "(" + pairs.join(",") + ")";
		}
		out = out === "" ? part : out + ">" + part;
		current = here.child;
	}
	return out;
}

test "nested paths join their parents' segments and capture params per screen" {
	assert describe(targetFromPath("shop/product/42", config)) === "Shop>Product(id=42)", describe(targetFromPath("shop/product/42", config));
	assert describe(targetFromPath("/shop/", config)) === "Shop>Catalog";
	assert describe(targetFromPath("shop/product/7/reviews", config)) === "Shop>Reviews(id=7)";
	assert describe(targetFromPath("shop/product/7/reviews/3", config)) === "Shop>Reviews(id=7,page=3)";
}

test "an exact path ignores its parent, the query lands on the leaf, escapes are decoded" {
	assert describe(targetFromPath("user/ana%20b?tab=likes&x", config)) === "Profile(name=ana b,tab=likes,x=)";
	assert decodeComponent("caf%C3%A9%2Fx%zz") === "café/x%zz", decodeComponent("caf%C3%A9%2Fx%zz");
}

test "a wildcard catches what no other pattern matches, ranked below every literal match" {
	assert describe(targetFromPath("nowhere/at/all", config)) === "Missing";
	assert describe(targetFromPath("shop/product/1", config)) === "Shop>Product(id=1)";
}

test "the longest matching prefix wins and a foreign URL is not a link" {
	const options: LinkingOptions = { prefixes: ["app://", "https://example.com", "https://example.com/app"], config };
	assert pathOf("https://example.com/app/shop", options.prefixes) === "/shop";
	assert describe(targetFromURL("app://shop/product/5", options)) === "Shop>Product(id=5)";
	assert targetFromURL("other://shop", options) === null;
}

test "a fragment after the query is dropped, not read into the last value" {
	const fragment = targetFromPath("user/ana?tab=likes#top", config);
	assert describe(fragment) === "Profile(name=ana,tab=likes)", describe(fragment);
	assert describe(targetFromPath("shop/product/4#top", config)) === "Shop>Product(id=4)";
}

function stateOfTarget(target: NavTarget): NavigationState {
	const child = target.child;
	return {
		index: 0,
		routeNames: [],
		routes: [{
			key: target.name,
			name: target.name,
			params: target.values,
			state: child === null ? null : stateOfTarget(child as NavTarget),
		}],
	};
}

function roundTrip(path: string): string {
	const target = targetFromPath(path, config);
	if (target === null) { return "no match"; }
	return pathFromState(stateOfTarget(target as NavTarget), config) ?? "null";
}

function routeOf(
	name: string,
	params: Map<string, string> | null,
	state: NavigationState | null,
): NavigationRoute {
	return { key: name, name, params, state };
}

function stateOf(index: int32, routes: NavigationRoute[]): NavigationState {
	return { index, routeNames: [], routes };
}

function paramsOf(key: string, value: string): Map<string, string> {
	const values = new Map<string, string>();
	values.set(key, value);
	return values;
}

test "pathFromState inverts targetFromPath for nested, optional, exact and wildcard patterns" {
	assert roundTrip("shop/product/42") === "/shop/product/42", roundTrip("shop/product/42");
	assert roundTrip("/shop/") === "/shop", roundTrip("/shop/");
	assert roundTrip("shop/product/7/reviews") === "/shop/product/7/reviews";
	assert roundTrip("shop/product/7/reviews/3") === "/shop/product/7/reviews/3";
	assert roundTrip("user/ana%20b") === "/user/ana%20b", roundTrip("user/ana%20b");
	const escaped = "user/caf%C3%A9%2Fx";
	assert roundTrip(escaped) === "/" + escaped, roundTrip(escaped);
	assert roundTrip("nowhere/at/all") === "/Missing", roundTrip("nowhere/at/all");
}

test "params no pattern claims become a sorted escaped query on the focused route only" {
	assert roundTrip("user/ana?tab=likes&a=1%262&x") === "/user/ana?a=1%262&tab=likes&x=",
		roundTrip("user/ana?tab=likes&a=1%262&x");
	const values = paramsOf("id", "9");
	values.set("sort", "asc");
	const product = routeOf("Product", values, null);
	const shop = routeOf("Shop", paramsOf("ignored", "1"), stateOf(0, [product]));
	assert pathFromState(stateOf(0, [shop]), config) === "/shop/product/9?sort=asc";
}

test "pathFromState reads the focused route of each level, tabs and stacks alike" {
	const tabs = stateOf(1, [
		routeOf("Shop", null, null),
		routeOf("Profile", paramsOf("name", "bo"), null),
	]);
	assert pathFromState(tabs, config) === "/user/bo";
	const pages = [
		routeOf("Catalog", null, null),
		routeOf("Product", paramsOf("id", "3"), null),
		routeOf("Reviews", paramsOf("id", "3"), null),
	];
	const second = stateOf(0, [routeOf("Shop", null, stateOf(1, pages))]);
	const third = stateOf(0, [routeOf("Shop", null, stateOf(2, pages))]);
	assert pathFromState(second, config) === "/shop/product/3";
	assert pathFromState(third, config) === "/shop/product/3/reviews";
}

test "a route the config does not name keeps its route name in the path" {
	assert pathFromState(stateOf(0, [routeOf("Settings", null, null)]), config) === "/Settings";
	const advanced = stateOf(0, [routeOf("Advanced", null, null)]);
	const deep = stateOf(0, [routeOf("Settings", null, advanced)]);
	assert pathFromState(deep, config) === "/Settings/Advanced";
	const gallery = stateOf(0, [routeOf("Gallery", null, null)]);
	const unmapped = stateOf(0, [routeOf("Shop", null, gallery)]);
	assert pathFromState(unmapped, config) === "/shop/Gallery";
}

test "a state with no routes or a missing required param has no path" {
	assert pathFromState(stateOf(0, []), config) === null;
	const bare = stateOf(0, [routeOf("Shop", null, stateOf(0, [routeOf("Product", null, null)]))]);
	assert pathFromState(bare, config) === null;
}

interface OrderParams {
	order: string;
}

const Orders = createStackNavigator<OrderParams>();

function OrderList(props: ScreenProps<OrderParams>): NeonNode {
	return <Text>orders</Text>;
}

function Order(props: ScreenProps<OrderParams>): NeonNode {
	const route = useRoute<OrderParams>();
	return <Text>{"order " + (route.params() === null ? "-" : (route.params() as OrderParams).order)}</Text>;
}

test "the initial URL from the host opens its screen once the container mounts" {
	const services = new FakeServices();
	services.initial = "orders://order/A17";
	services.install();
	const ref = createNavigationContainerRef();
	const root: MockNode = mockNode("root");
	const linking: LinkingOptions = {
		prefixes: ["orders://"],
		config: { screens: [{ name: "OrderList", path: "" }, { name: "Order", path: "order/:order" }] },
	};
	const dispose: Dispose = render(<NavigationContainer ref={ref} linking={linking}>
		<Orders.Navigator>
			<Orders.Screen name="OrderList" component={OrderList} />
			<Orders.Screen name="Order" component={Order}
				parseParams={(values: Map<string, string>): OrderParams => ({ order: values.get("order") ?? "" })} />
		</Orders.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	const seen = await Linking.getInitialURL();
	assert seen === "orders://order/A17";
	assert ref.currentPath() === "Order", ref.currentPath();
	assert visibleText(root) === "‹ OrderList|Order|order A17", visibleText(root);
	ref.goBack();
	assert visibleText(root) === "OrderList|orders", visibleText(root);
	publishUrl("orders://order/B2");
	assert visibleText(root) === "‹ OrderList|Order|order B2", visibleText(root);
	dispose();
}
