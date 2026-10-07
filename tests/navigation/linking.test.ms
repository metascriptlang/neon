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
	ScreenProps,
	createNavigationContainerRef,
	createStackNavigator,
	decodeComponent,
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
	const dispose: Dispose = render(<NavigationContainer navigationRef={ref} linking={linking}>
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
