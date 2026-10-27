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
	QueryParams,
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
			for (const key of (values as QueryParams).names) {
				if (keys.indexOf(key) < 0) { keys.push(key); }
			}
			keys.sort();
			const pairs: string[] = [];
			for (const key of keys) { pairs.push(key + "=" + (values as QueryParams).getAll(key).join("|")); }
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

test "the first matching prefix wins and a foreign URL is not a link" {
	const options: LinkingOptions = { prefixes: ["app://", "https://example.com", "https://example.com/app"], config };
	assert pathOf("https://example.com/app/shop", options.prefixes) === "/app/shop";
	assert pathOf("https://example.com/app/shop", ["https://example.com/app", "https://example.com"]) === "/shop";
	assert describe(targetFromURL("app://shop/product/5", options)) === "Shop>Product(id=5)";
	assert targetFromURL("other://shop", options) === null;
}

test "a prefix matches only at a host boundary" {
	const prefixes = ["https://x.com"];
	assert pathOf("https://x.com.evil.com/shop", prefixes) === null;
	assert pathOf("https://x.comevil/shop", prefixes) === null;
	assert pathOf("https://x.com/a", prefixes) === "/a";
	assert pathOf("https://x.com?q=1", prefixes) === "/?q=1";
	assert pathOf("https://x.com#top", prefixes) === "/#top";
	assert pathOf("https://x.com", prefixes) === "";
	assert pathOf("https://x.com//a//b", prefixes) === "/a/b";
	assert pathOf("https://x.com/", ["https://x.com/"]) === "";
	assert pathOf("https://x.com/app/a", ["https://x.com/app"]) === "/a";
	assert pathOf("https://x.com/apple", ["https://x.com/app"]) === null;
}

test "a wildcard label in a prefix stands for one or more host characters" {
	const prefixes = ["https://*.example.com"];
	assert pathOf("https://a.example.com/shop", prefixes) === "/shop";
	assert pathOf("https://a.b.example.com/shop", prefixes) === "/shop";
	assert pathOf("https://example.com/shop", prefixes) === null;
	assert pathOf("https://.example.com/shop", prefixes) === null;
	assert pathOf("https://a.example.com.evil.com/shop", prefixes) === null;
	assert pathOf("https://a/b.example.com/shop", prefixes) === null;
	assert pathOf("https://aXexample.com/shop", prefixes) === null;
	assert pathOf("https://a.example.com?x=1", prefixes) === "/?x=1";
}

test "a plus in the query is a space and a plus in the path stays a plus" {
	assert describe(targetFromPath("user/ana?tab=a+b&c+d=e", config)) === "Profile(c d=e,name=ana,tab=a b)";
	assert describe(targetFromPath("user/a+b?tab=a%2Bb", config)) === "Profile(name=a+b,tab=a+b)";
}

test "a query value keeps the raw text of every escape that is not valid UTF-8" {
	assert describe(targetFromPath("user/ana?q=caf%C3%A9%zz", config)) === "Profile(name=ana,q=café%zz)";
	assert describe(targetFromPath("user/ana?q=%e4%bd%a0", config)) === "Profile(name=ana,q=\u4f60)";
	assert describe(targetFromPath("user/ana?q=%41%FF", config)) === "Profile(name=ana,q=A%FF)";
	assert describe(targetFromPath("user/ana?q=%E4%BD", config)) === "Profile(name=ana,q=%E4%BD)";
	assert describe(targetFromPath("user/ana?q=%C0%80", config)) === "Profile(name=ana,q=%C0%80)";
	assert describe(targetFromPath("user/ana?q=%ED%A0%80", config)) === "Profile(name=ana,q=%ED%A0%80)";
	assert describe(targetFromPath("user/ana?q=%F4%90%80%80", config)) === "Profile(name=ana,q=%F4%90%80%80)";
	assert describe(targetFromPath("user/ana?q=%F0%9F%98%80%", config)) === "Profile(name=ana,q=\u{1F600}%)";
	assert describe(targetFromPath("user/ana?q=100%", config)) === "Profile(name=ana,q=100%)";
}

test "one leading query mark is dropped and surrounding blanks are trimmed" {
	assert describe(targetFromPath("user/ana??q=1", config)) === "Profile(name=ana,q=1)";
	assert describe(targetFromPath("user/ana?q=1 ", config)) === "Profile(name=ana,q=1)";
}

test "a path param that fails to decode rejects its route and the next candidate is tried" {
	assert describe(targetFromPath("shop/product/%zz", config)) === "Missing";
	assert describe(targetFromPath("shop/product/%E4%BD", config)) === "Missing";
	assert describe(targetFromPath("shop/product/%FF", config)) === "Missing";
	assert describe(targetFromPath("shop/product/100%", config)) === "Missing";
	assert describe(targetFromPath("user/a%C0%80", config)) === "Missing";
	assert describe(targetFromPath("shop/product/%e4%bd%a0", config)) === "Shop>Product(id=\u4f60)";
	assert targetFromPath("shop/product/%zz", { screens: [{ name: "Product", path: "shop/product/:id" }] }) === null;
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
	params: QueryParams | null,
	state: NavigationState | null,
): NavigationRoute {
	return { key: name, name, params, state };
}

function stateOf(index: int32, routes: NavigationRoute[]): NavigationState {
	return { index, routeNames: [], routes };
}

function paramsOf(key: string, value: string): QueryParams {
	const values = new QueryParams();
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

test "a repeated query key keeps every value in order and round trips to the same path" {
	const options: LinkingOptions = { prefixes: ["myapp://"], config: { screens: [{ name: "Feed", path: "feed" }] } };
	const target = targetFromURL("myapp://feed?tag=a&tag=b", options) as NavTarget;
	const values = target.values as QueryParams;
	assert values.getAll("tag").join(",") === "a,b", values.getAll("tag").join(",");
	assert values.get("tag") === "a";
	assert pathFromState(stateOfTarget(target), options.config) === "/feed?tag=a&tag=b",
		pathFromState(stateOfTarget(target), options.config) ?? "null";
}

test "a bare query key is present with an empty value" {
	const options: LinkingOptions = { prefixes: ["myapp://"], config: { screens: [{ name: "Feed", path: "feed" }] } };
	const values = (targetFromURL("myapp://feed?flag", options) as NavTarget).values as QueryParams;
	assert values.has("flag");
	assert values.get("flag") === "";
	assert values.getAll("flag").length === 1;
}

test "a query key that names a path param replaces the path value once and then repeats" {
	const values = (targetFromPath("user/ana?name=bob&name=cy", config) as NavTarget).values as QueryParams;
	assert values.getAll("name").join(",") === "bob,cy", values.getAll("name").join(",");
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

interface OrdersParams {
	OrderList: null;
	Order: OrderParams;
}

const Orders = createStackNavigator<OrdersParams>();

function OrderList(props: ScreenProps<OrdersParams>): NeonNode {
	return <Text>orders</Text>;
}

function Order(props: ScreenProps<OrdersParams>): NeonNode {
	const route = useRoute<OrdersParams, "Order">();
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
				params={Orders.params.of("Order", {
					parse: (values: QueryParams): OrderParams => ({ order: values.get("order") ?? "" }),
				})} />
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

interface KeptParams {
	values: QueryParams;
}

interface KeptOrdersParams {
	OrderList: null;
	Order: KeptParams;
}

const Kept = createStackNavigator<KeptOrdersParams>();

function KeptList(props: ScreenProps<KeptOrdersParams>): NeonNode {
	return <Text>orders</Text>;
}

function KeptOrder(props: ScreenProps<KeptOrdersParams>): NeonNode {
	return <Text>order</Text>;
}

test "the initial URL keeps every value of a repeated query key in the exported state" {
	const services = new FakeServices();
	services.initial = "orders://order/A17?tag=a&tag=b&flag";
	services.install();
	const ref = createNavigationContainerRef();
	const root: MockNode = mockNode("root");
	const linking: LinkingOptions = {
		prefixes: ["orders://"],
		config: { screens: [{ name: "OrderList", path: "" }, { name: "Order", path: "order/:order" }] },
	};
	const dispose: Dispose = render(<NavigationContainer ref={ref} linking={linking}>
		<Kept.Navigator>
			<Kept.Screen name="OrderList" component={KeptList} />
			<Kept.Screen name="Order" component={KeptOrder}
				params={Kept.params.of("Order", {
					parse: (values: QueryParams): KeptParams => ({ values }),
					stringify: (params: KeptParams): QueryParams => params.values,
				})} />
		</Kept.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	await Linking.getInitialURL();
	const state: NavigationState = ref.getRootState();
	const route = state.routes[state.index];
	assert route.name === "Order", route.name;
	const params = route.params as QueryParams;
	assert params.getAll("tag").join(",") === "a,b", params.getAll("tag").join(",");
	assert params.has("flag") && params.get("flag") === "";
	assert params.get("order") === "A17";
	dispose();
}
