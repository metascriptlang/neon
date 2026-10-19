import { createRoot } from "../../src/core/owner";
import { flush } from "../../src/core/runtime";
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
	NavigationAction,
	NavigationEventArg,
	ScreenProps,
	createBottomTabNavigator,
	createDrawerNavigator,
	createMemoryRoutingHistory,
	createNavigationContainerRef,
	createRoutingSession,
	createStackNavigator,
} from "../../src/navigation/index";
import { findLabel, settle, visibleText } from "./navHarness";

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

function Profile(props: ScreenProps<string>): NeonNode {
	return <Text>profile</Text>;
}

const visitLinking: LinkingOptions = {
	prefixes: [],
	enabled: false,
	config: {
		screens: [
			{ name: "Feed", path: "feed" },
			{ name: "Inbox", path: "inbox" },
			{ name: "Profile", path: "profile" },
		],
	},
};

function visitShell(): NeonNode {
	return <Tabs.Navigator backBehavior="history">
		<Tabs.Screen name="Feed" component={Feed} />
		<Tabs.Screen name="Inbox" component={Inbox} />
		<Tabs.Screen name="Profile" component={Profile} />
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
	log.mounts = "";
	app.ref.goBack();
	const popped = take();
	assert popped === "go -1;", popped;
	settle();
	assert log.mounts === "", "the popped product leaves without mounting again: " + log.mounts;
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

test "a switch away from the first tab adds an entry that back leaves, in the app as in the browser" {
	const app = startWith({ url: "/feed", state: "" }, tabShell, tabLinking);
	take();
	app.ref.navigate("Inbox");
	const switched = take();
	assert switched === "push /inbox;", switched;
	assert app.memory.index() === 1, app.memory.index().toString();
	assert visibleText(app.root).indexOf("inbox") >= 0, visibleText(app.root);
	assert app.memory.go(-1);
	assert app.ref.currentPath() === "Feed", app.ref.currentPath();
	assert app.memory.go(1);
	assert app.ref.currentPath() === "Inbox", app.ref.currentPath();
	assert take() === "", "a traversal writes nothing";
	app.ref.goBack();
	const back = take();
	assert back === "go -1;", back;
	assert app.ref.currentPath() === "Feed", app.ref.currentPath();
	assert finish(app) === 0, "routing errors";
}

test "tabs with a history back behavior walk the visits back in the browser" {
	const app = startWith({ url: "/feed", state: "" }, visitShell, visitLinking);
	take();
	app.ref.navigate("Inbox");
	app.ref.navigate("Profile");
	const visited = take();
	assert visited === "push /inbox;push /profile;", visited;
	app.ref.navigate("Inbox");
	const revisited = take();
	assert revisited === "go -1;replace /profile;push /inbox;", revisited;
	assert app.memory.go(-1);
	assert app.ref.currentPath() === "Profile", app.ref.currentPath();
	assert app.memory.go(-1);
	assert app.ref.currentPath() === "Feed", app.ref.currentPath();
	assert app.memory.go(2);
	assert app.ref.currentPath() === "Inbox", app.ref.currentPath();
	assert take() === "", "a traversal writes nothing";
	app.ref.goBack();
	assert take() === "go -1;";
	assert app.ref.currentPath() === "Profile", app.ref.currentPath();
	assert finish(app) === 0, "routing errors";
}

test "a reload restores the selected tab from its stored keys" {
	const first = startWith({ url: "/feed", state: "" }, tabShell, tabLinking);
	first.ref.navigate("Inbox");
	const stored = first.memory.read();
	assert finish(first) === 0, "routing errors";
	const app = startWith(stored, tabShell, tabLinking);
	assert visibleText(app.root).indexOf("inbox") >= 0, visibleText(app.root);
	assert app.memory.read().state === stored.state, "the restored keys are the stored keys";
	assert finish(app) === 0, "routing errors";
}

function drawerOpen(app: App): boolean {
	return findLabel(app.root, "Close navigation menu") !== null;
}

test "opening the drawer adds an entry at the same address, and browser back closes it" {
	const app = startWith({ url: "/", state: "" }, drawerShell, drawerLinking);
	app.ref.navigate("Inbox");
	const switched = take();
	assert switched === "replace /;replace /;push /inbox;", switched;
	app.ref.openDrawer();
	flush();
	const opened = take();
	assert opened === "push /inbox;", opened;
	assert drawerOpen(app), "drawer open";
	assert app.memory.go(-1);
	flush();
	assert !drawerOpen(app), "browser back closed the drawer";
	assert app.ref.currentPath() === "Main>Inbox", app.ref.currentPath();
	assert app.memory.go(1);
	flush();
	assert drawerOpen(app), "browser forward opened it again";
	assert take() === "", "a traversal writes nothing";
	app.ref.closeDrawer();
	flush();
	const closed = take();
	assert closed === "go -1;", closed;
	assert app.memory.read().url === "/inbox", app.memory.read().url;
	assert finish(app) === 0, "routing errors";
}

test "a reload on an open drawer's entry restores its page with the drawer closed" {
	const first = startWith({ url: "/", state: "" }, drawerShell, drawerLinking);
	first.ref.openDrawer();
	const stored = first.memory.read();
	assert finish(first) === 0, "routing errors";
	const app = startWith(stored, drawerShell, drawerLinking);
	assert app.ref.currentPath() === "Main>Feed", app.ref.currentPath();
	assert !drawerOpen(app), "the drawer starts closed";
	assert finish(app) === 0, "routing errors";
}

let refused: NavigationAction | null = null;

test "browser back stays on a screen whose beforeRemove prevents it" {
	const app = startApp({ url: "/", state: "" });
	assert app.ref.linkTo("/shop/product/5");
	take();
	refused = null;
	const product = log.product as Navigation<ItemParams>;
	const stop = product.addListener("beforeRemove", (e: NavigationEventArg): void => {
		e.preventDefault();
		refused = e.data.action;
	});
	assert app.memory.go(-1);
	assert app.ref.currentPath() === "Shop>Product", app.ref.currentPath();
	assert app.memory.read().url === "/shop/product/5", app.memory.read().url;
	const back = take();
	assert back === "go 1;", "the session returns to the screen it kept: " + back;
	assert refused !== null && (refused as NavigationAction).type === "GO_BACK";
	stop();
	product.dispatch(refused as NavigationAction);
	assert app.ref.currentPath() === "Shop>Catalog", app.ref.currentPath();
	const left = take();
	assert left === "go -1;", left;
	assert app.memory.read().url === "/shop", app.memory.read().url;
	assert finish(app) === 0, "routing errors";
}

test "setParams replaces the entry it changes and keeps the ones below" {
	const app = startApp({ url: "/", state: "" });
	assert app.ref.linkTo("/shop/product/5");
	take();
	(log.product as Navigation<ItemParams>).setParams({ id: "6" });
	flush();
	const replaced = take();
	assert replaced === "replace /shop/product/6;", replaced;
	assert app.memory.index() === 2, app.memory.index().toString();
	assert app.memory.read().url === "/shop/product/6", app.memory.read().url;
	assert visibleText(app.root).indexOf("product 6") >= 0, visibleText(app.root);
	assert app.memory.go(-1);
	assert app.ref.currentPath() === "Shop>Catalog", app.ref.currentPath();
	assert app.memory.go(-1);
	assert app.ref.currentPath() === "Home", app.ref.currentPath();
	assert app.memory.go(2);
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

test "routing history refuses a nested screen with an exact path" {
	const exactLinking: LinkingOptions = {
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
						{ name: "Product", path: "product/:id", exact: true },
					],
				},
			],
		},
	};
	const registry = new RoutingRegistry("main");
	let message = "";
	const dispose = createRoot((stop: Dispose): Dispose => {
		try {
			NavigationContainer({
				children: shell(),
				linking: exactLinking,
				routing: { registry, scope: "main" },
			});
		} catch (e) {
			message = (e as Error).message;
		}
		return stop;
	});
	dispose();
	assert message === "NavigationContainer: routing history joins each level's path, so screen " +
		"'Product' cannot take an exact path", message;
}

test "a traversal to an entry whose nested stored key does not decode opens its address" {
	const app = startApp({ url: "/", state: "" });
	assert app.ref.linkTo("/shop/product/5");
	const stored = app.memory.read();
	assert stored.state.includes(":true"), stored.state;
	app.memory.replace({ url: stored.url, state: stored.state.replace(":true", ":maybe") });
	assert app.memory.go(-2);
	assert app.ref.currentPath() === "Home", app.ref.currentPath();
	take();
	assert app.memory.go(2);
	assert app.ref.currentPath() === "Shop>Product", app.ref.currentPath();
	assert visibleText(app.root).indexOf("product 5") >= 0, visibleText(app.root);
	assert finish(app) === 0, "routing errors";
}
