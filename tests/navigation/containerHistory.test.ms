import { createRoot } from "../../src/core/owner";
import { Dispose } from "../../src/core/types";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockHost, mockNode } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	LinkingOptions,
	NavigationContainer,
	NavigationContainerRef,
	RoutingError,
	RoutingHistory,
	RoutingHistoryEntry,
	RoutingRegistry,
	RoutingSession,
	Navigation,
	ScreenProps,
	createBottomTabNavigator,
	createDrawerNavigator,
	createMemoryRoutingHistory,
	createNavigationContainerRef,
	createRoutingSession,
	createStackNavigator,
} from "../../src/navigation/index";
import { findLabel, visibleText } from "./navHarness";

interface ItemParams {
	id: string;
}

interface Log {
	lines: string;
	mounts: string;
	product: Navigation<ItemParams> | null;
}

const Root = createStackNavigator<string>();
const Shop = createStackNavigator<ItemParams>();
const Tabs = createBottomTabNavigator<string>();
const Menu = createDrawerNavigator<string>();

const linking: LinkingOptions = {
	prefixes: [],
	enabled: false,
	config: {
		screens: [
			{ name: "Home", path: "" },
			{
				name: "Shop",
				path: "shop",
				screens: [
					{ name: "Catalog", path: "" },
					{ name: "Product", path: "product/:id" },
				],
			},
		],
	},
};

const tabLinking: LinkingOptions = {
	prefixes: [],
	enabled: false,
	config: { screens: [{ name: "Feed", path: "feed" }, { name: "Inbox", path: "inbox" }] },
};

const drawerLinking: LinkingOptions = {
	prefixes: [],
	enabled: false,
	config: {
		screens: [
			{
				name: "Main",
				path: "",
				screens: [{ name: "Feed", path: "" }, { name: "Inbox", path: "inbox" }],
			},
			{ name: "Details", path: "details" },
		],
	},
};

const log: Log = { lines: "", mounts: "", product: null };

function Home(props: ScreenProps<string>): NeonNode {
	log.mounts += "home;";
	return <Text>home</Text>;
}

function Catalog(props: ScreenProps<ItemParams>): NeonNode {
	log.mounts += "catalog;";
	return <Text>catalog</Text>;
}

function Product(props: ScreenProps<ItemParams>): NeonNode {
	const params = props.route.params;
	log.mounts += "product;";
	log.product = props.navigation;
	return <Text>{"product " + (params() === null ? "-" : (params() as ItemParams).id)}</Text>;
}

function ShopScreen(props: ScreenProps<string>): NeonNode {
	return <Shop.Navigator>
		<Shop.Screen name="Catalog" component={Catalog} />
		<Shop.Screen name="Product" component={Product}
			parseParams={(values: Map<string, string>): ItemParams => {
				return { id: values.get("id") ?? "" };
			}}
			stringifyParams={(params: ItemParams): Map<string, string> => {
				const values = new Map<string, string>();
				values.set("id", params.id);
				return values;
			}} />
	</Shop.Navigator>;
}

function shell(): NeonNode {
	return <Root.Navigator>
		<Root.Screen name="Home" component={Home} />
		<Root.Screen name="Shop" component={ShopScreen} />
	</Root.Navigator>;
}

function Feed(props: ScreenProps<string>): NeonNode {
	return <Text>feed</Text>;
}

function Inbox(props: ScreenProps<string>): NeonNode {
	return <Text>inbox</Text>;
}

function Details(props: ScreenProps<string>): NeonNode {
	return <Text>details</Text>;
}

function tabShell(): NeonNode {
	return <Tabs.Navigator>
		<Tabs.Screen name="Feed" component={Feed} />
		<Tabs.Screen name="Inbox" component={Inbox} />
	</Tabs.Navigator>;
}

function MainScreen(props: ScreenProps<string>): NeonNode {
	return <Menu.Navigator>
		<Menu.Screen name="Feed" component={Feed} />
		<Menu.Screen name="Inbox" component={Inbox} />
	</Menu.Navigator>;
}

function drawerShell(): NeonNode {
	return <Root.Navigator>
		<Root.Screen name="Main" component={MainScreen} />
		<Root.Screen name="Details" component={Details} />
	</Root.Navigator>;
}

function recorded(memory: RoutingHistory): RoutingHistory {
	return {
		writable: true,
		read: memory.read,
		index: memory.index,
		push: (entry: RoutingHistoryEntry): void => {
			log.lines += "push " + entry.url + ";";
			memory.push(entry);
		},
		replace: (entry: RoutingHistoryEntry): void => {
			log.lines += "replace " + entry.url + ";";
			memory.replace(entry);
		},
		go: (delta: int32): boolean => {
			log.lines += "go " + delta.toString() + ";";
			return memory.go(delta);
		},
		listen: memory.listen,
	};
}

interface App {
	root: MockNode;
	ref: NavigationContainerRef;
	memory: RoutingHistory;
	session: RoutingSession;
	errors: RoutingError[];
	stop: Dispose;
	dispose: Dispose;
}

function startApp(entry: RoutingHistoryEntry): App {
	return startWith(entry, shell, linking);
}

function startWith(
	entry: RoutingHistoryEntry,
	content: () => NeonNode,
	options: LinkingOptions,
): App {
	log.lines = "";
	log.mounts = "";
	const registry = new RoutingRegistry("main");
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const memory = createMemoryRoutingHistory(entry);
	const errors: RoutingError[] = [];
	let opened: RoutingSession | null = null;
	const dispose = createRoot((stop: Dispose): Dispose => {
		const container = NavigationContainer({
			children: content(),
			linking: options,
			ref,
			routing: { registry, scope: "main" },
		});
		const created = createRoutingSession(
			registry,
			recorded(memory),
			(failure: RoutingError): void => { errors.push(failure); },
		);
		if (!created.ok) { throw new Error("session: " + created.error.toString()); }
		opened = created.value;
		container(mockHost(), root as unknown as HostNode, null);
		return stop;
	});
	const session = opened as RoutingSession;
	const stop = ref.enableHistory(session);
	return { root, ref, memory, session, errors, stop, dispose };
}

function take(): string {
	const lines = log.lines;
	log.lines = "";
	return lines;
}

function finish(app: App): int32 {
	app.stop();
	app.session.dispose();
	app.dispose();
	return app.errors.length as int32;
}

test "an in-app navigation reaches the history without a sync" {
	const app = startApp({ url: "/", state: "" });
	const enabled = take();
	assert enabled === "replace /;replace /;", "the session opens, then enabling replaces: " + enabled;
	assert app.ref.linkTo("/shop/product/5");
	const pushed = take();
	assert pushed === "push /shop;push /shop/product/5;", pushed;
	assert app.memory.read().url === "/shop/product/5", app.memory.read().url;
	app.ref.goBack();
	const popped = take();
	assert popped === "go -1;", popped;
	assert app.memory.read().url === "/shop", app.memory.read().url;
	app.ref.goBack();
	assert take() === "go -1;";
	assert app.memory.read().url === "/", app.memory.read().url;
	assert app.ref.currentPath() === "Home", app.ref.currentPath();
	assert finish(app) === 0, "routing errors";
}

test "browser back and forward drive the container's navigators and write nothing" {
	const app = startApp({ url: "/", state: "" });
	assert app.ref.linkTo("/shop/product/5");
	take();
	assert app.memory.go(-1);
	assert app.ref.currentPath() === "Shop>Catalog", app.ref.currentPath();
	assert app.memory.go(-1);
	assert app.ref.currentPath() === "Home", app.ref.currentPath();
	assert visibleText(app.root).indexOf("home") >= 0, visibleText(app.root);
	assert app.memory.go(2);
	assert app.ref.currentPath() === "Shop>Product", app.ref.currentPath();
	assert visibleText(app.root).indexOf("product 5") >= 0, visibleText(app.root);
	assert app.ref.canGoBack(), "the catalog below the product comes back";
	const written = take();
	assert written === "", "a traversal writes nothing: " + written;
	assert finish(app) === 0, "routing errors";
}

test "a traversal keeps the screens whose keys it restores" {
	const app = startApp({ url: "/", state: "" });
	assert app.ref.linkTo("/shop/product/5");
	assert log.mounts === "home;catalog;product;", log.mounts;
	assert app.memory.go(-1);
	log.mounts = "";
	assert app.memory.go(1);
	assert log.mounts === "product;", "only the popped product mounts again: " + log.mounts;
	assert finish(app) === 0, "routing errors";
}

test "a reload restores the stored tree before mount and keeps its keys" {
	const first = startApp({ url: "/", state: "" });
	assert first.ref.linkTo("/shop/product/5");
	const stored = first.memory.read();
	assert finish(first) === 0, "routing errors";
	const app = startApp(stored);
	assert app.ref.currentPath() === "Shop>Product", app.ref.currentPath();
	assert visibleText(app.root).indexOf("product 5") >= 0, visibleText(app.root);
	assert app.ref.canGoBack(), "the catalog below the product is restored";
	const enabled = take();
	assert enabled === "replace /shop/product/5;replace /shop/product/5;", enabled;
	assert app.memory.read().state === stored.state, "the restored keys are the stored keys";
	app.ref.goBack();
	const popped = take();
	assert popped === "replace /shop;", "a pop past the first entry replaces it: " + popped;
	assert finish(app) === 0, "routing errors";
}

test "a tab switch replaces the entry" {
	const app = startWith({ url: "/feed", state: "" }, tabShell, tabLinking);
	take();
	app.ref.navigate("Inbox");
	const switched = take();
	assert switched === "replace /inbox;", switched;
	assert app.memory.index() === 0, app.memory.index().toString();
	assert visibleText(app.root).indexOf("inbox") >= 0, visibleText(app.root);
	assert finish(app) === 0, "routing errors";
}

test "a traversal lands with the drawer closed" {
	const app = startWith({ url: "/", state: "" }, drawerShell, drawerLinking);
	app.ref.navigate("Details");
	assert take() === "replace /;replace /;push /details;";
	assert app.memory.go(-1);
	app.ref.openDrawer();
	assert findLabel(app.root, "Close navigation menu") !== null, "drawer open";
	assert app.memory.go(1);
	assert app.ref.currentPath() === "Details", app.ref.currentPath();
	assert app.memory.go(-1);
	assert findLabel(app.root, "Close navigation menu") === null, "the traversal closed the drawer";
	assert take() === "", "a traversal writes nothing";
	assert finish(app) === 0, "routing errors";
}

test "setParams rewrites the entry it changes" {
	const app = startApp({ url: "/", state: "" });
	assert app.ref.linkTo("/shop/product/5");
	take();
	(log.product as Navigation<ItemParams>).setParams({ id: "6" });
	assert app.memory.read().url === "/shop/product/6", app.memory.read().url;
	assert visibleText(app.root).indexOf("product 6") >= 0, visibleText(app.root);
	assert app.memory.go(-1);
	assert app.ref.currentPath() === "Shop>Catalog", app.ref.currentPath();
	assert app.memory.go(1);
	assert visibleText(app.root).indexOf("product 6") >= 0, visibleText(app.root);
	assert finish(app) === 0, "routing errors";
}

test "enableHistory needs routing and a mounted container" {
	const app = startApp({ url: "/", state: "" });
	const plain = createNavigationContainerRef();
	const routed = createNavigationContainerRef();
	const registry = new RoutingRegistry("main");
	let unrouted = "";
	let unmounted = "";
	const dispose = createRoot((stop: Dispose): Dispose => {
		const container = NavigationContainer({ children: shell(), linking, ref: plain });
		container(mockHost(), mockNode("plain") as unknown as HostNode, null);
		NavigationContainer({
			children: shell(),
			linking,
			ref: routed,
			routing: { registry, scope: "main" },
		});
		return stop;
	});
	try { plain.enableHistory(app.session); } catch (e) { unrouted = (e as Error).message; }
	try { routed.enableHistory(app.session); } catch (e) { unmounted = (e as Error).message; }
	assert unrouted === "enableHistory: the NavigationContainer has no routing", unrouted;
	assert unmounted === "enableHistory: the NavigationContainer is not mounted yet", unmounted;
	dispose();
	assert finish(app) === 0, "routing errors";
}
