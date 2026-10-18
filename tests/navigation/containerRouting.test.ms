import { Signal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { Dispose } from "../../src/core/types";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockHost, mockNode, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	LinkingOptions,
	NavigationContainer,
	NavigationContainerRef,
	NavigationState,
	RouteCodec,
	RoutePlan,
	RoutingError,
	RoutingHistory,
	RoutingParticipant,
	RoutingRegistry,
	RoutingSession,
	ScreenProps,
	bindRoute,
	createMemoryRoutingHistory,
	createNavigationContainerRef,
	createRequestRoutingHistory,
	createRouteParticipant,
	createRoutingSession,
	createStackNavigator,
	decodeRouteComponent,
	encodeRouteComponent,
} from "../../src/navigation/index";
import { visibleText } from "./navHarness";

interface ItemParams {
	id: string;
}

const Root = createStackNavigator<string>();
const Shop = createStackNavigator<ItemParams>();

const linking: LinkingOptions = {
	prefixes: [],
	enabled: false,
	config: {
		screens: [
			{ name: "Home", path: "" },
			{ name: "Ghost", path: "ghost" },
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

function Home(props: ScreenProps<string>): NeonNode {
	return <Text>home</Text>;
}

function Catalog(props: ScreenProps<ItemParams>): NeonNode {
	return <Text>catalog</Text>;
}

function Product(props: ScreenProps<ItemParams>): NeonNode {
	const params = props.route.params;
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

interface App {
	root: MockNode;
	ref: NavigationContainerRef;
	dispose: Dispose;
}

function startApp(registry: RoutingRegistry, scope: string, beforeMount: () => void): App {
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = createRoot((stop: Dispose): Dispose => {
		const container = NavigationContainer({
			children: shell(),
			linking,
			ref,
			routing: { registry, scope },
		});
		beforeMount();
		container(mockHost(), root as unknown as HostNode, null);
		return stop;
	});
	return { root, ref, dispose };
}

function nothing(): void {}

function open(
	registry: RoutingRegistry,
	history: RoutingHistory,
	errors: RoutingError[],
): RoutingSession {
	const created = createRoutingSession(
		registry,
		history,
		(failure: RoutingError): void => { errors.push(failure); },
	);
	if (!created.ok) { throw new Error("session: " + created.error.toString()); }
	return created.value;
}

function addressOf(registry: RoutingRegistry): string {
	const address = registry.address();
	if (address.ok) { return address.value; }
	return "error " + address.error.toString();
}

function namedParticipant(
	scope: string,
	prefix: string,
	held: Signal<string>,
): RoutingParticipant {
	const codec: RouteCodec<string> = {
		id: scope,
		decode: (address: string): Result<string, RoutingError> => {
			if (!address.startsWith(prefix)) { return Result.err(RoutingError.NoMatch); }
			return decodeRouteComponent(address.substring(prefix.length, address.length));
		},
		encode: (name: string): Result<string, RoutingError> => {
			return Result.ok(prefix + encodeRouteComponent(name));
		},
	};
	return createRouteParticipant(
		scope,
		[bindRoute<string>(
			codec,
			(): string | null => held.get() === "" ? null : held.get(),
			(name: string): void => held.set(name),
		)],
		(): void => held.set(""),
		(): string => held.get(),
		(state: string): Result<RoutePlan, RoutingError> => {
			return Result.ok({ commit: (): void => held.set(state) });
		},
	);
}

test "a request URL applied before the container mounts opens the nested screen at mount" {
	const registry = new RoutingRegistry("main");
	const errors: RoutingError[] = [];
	let early = "";
	const app = startApp(registry, "main", (): void => {
		open(registry, createRequestRoutingHistory("/shop/product/42"), errors);
		early = addressOf(registry);
	});
	assert errors.length === 0;
	assert early === "/shop/product/42", early;
	assert app.ref.currentPath() === "Shop>Product", app.ref.currentPath();
	assert visibleText(app.root).indexOf("product 42") >= 0, visibleText(app.root);
	assert addressOf(registry) === "/shop/product/42", addressOf(registry);
	assert app.ref.canGoBack(), "the catalog below the product is kept";
	app.dispose();
}

test "a writable history opened before mount records the URL the container will open" {
	const registry = new RoutingRegistry("main");
	const errors: RoutingError[] = [];
	const history = createMemoryRoutingHistory({ url: "/shop/product/42", state: "" });
	let session: RoutingSession | null = null;
	const app = startApp(registry, "main", (): void => {
		session = open(registry, history, errors);
	});
	assert history.read().url === "/shop/product/42", history.read().url;
	assert app.ref.currentPath() === "Shop>Product", app.ref.currentPath();
	assert visibleText(app.root).indexOf("product 42") >= 0, visibleText(app.root);
	assert addressOf(registry) === "/shop/product/42", addressOf(registry);
	assert errors.length === 0;
	(session as RoutingSession).dispose();
	app.dispose();
}

test "memory history push and back move the built-in navigators" {
	const registry = new RoutingRegistry("main");
	const app = startApp(registry, "main", nothing);
	const errors: RoutingError[] = [];
	const history = createMemoryRoutingHistory({ url: "/", state: "" });
	const session = open(registry, history, errors);
	assert addressOf(registry) === "/", addressOf(registry);
	assert session.navigate("/shop/product/42", false).ok;
	assert session.navigate("/shop/product/7", false).ok;
	assert app.ref.currentPath() === "Shop>Product", app.ref.currentPath();
	assert visibleText(app.root).indexOf("product 7") >= 0, visibleText(app.root);
	assert addressOf(registry) === "/shop/product/7", addressOf(registry);
	assert history.go(-1);
	assert visibleText(app.root).indexOf("product 42") >= 0, visibleText(app.root);
	assert addressOf(registry) === "/shop/product/42", addressOf(registry);
	assert history.go(-1);
	assert app.ref.currentPath() === "Home", app.ref.currentPath();
	assert visibleText(app.root).indexOf("home") >= 0, visibleText(app.root);
	assert history.go(1);
	assert history.go(1);
	assert visibleText(app.root).indexOf("product 7") >= 0, visibleText(app.root);
	assert errors.length === 0;
	session.dispose();
	app.dispose();
}

test "navigating in the app updates the registry address and a sync records it" {
	const registry = new RoutingRegistry("main");
	const app = startApp(registry, "main", nothing);
	const errors: RoutingError[] = [];
	const history = createMemoryRoutingHistory({ url: "/", state: "" });
	const session = open(registry, history, errors);
	assert app.ref.linkTo("/shop/product/5");
	assert addressOf(registry) === "/shop/product/5", addressOf(registry);
	assert session.sync(false).ok;
	assert history.read().url === "/shop/product/5";
	assert history.go(-1);
	assert app.ref.currentPath() === "Home", app.ref.currentPath();
	assert history.go(1);
	assert visibleText(app.root).indexOf("product 5") >= 0, visibleText(app.root);
	assert errors.length === 0;
	session.dispose();
	app.dispose();
}

test "a custom participant in a second scope works independently beside the container" {
	const registry = new RoutingRegistry("main");
	const inspector = new Signal<string>("");
	registry.register(namedParticipant("inspector", "/materials/", inspector));
	const app = startApp(registry, "main", nothing);
	const errors: RoutingError[] = [];
	const history = createMemoryRoutingHistory({ url: "/", state: "" });
	const session = open(registry, history, errors);
	assert session.navigate("/shop/product/7?__nav.inspector=%2Fmaterials%2Fmetal", false).ok;
	assert app.ref.currentPath() === "Shop>Product", app.ref.currentPath();
	assert inspector.get() === "metal";
	inspector.set("wood");
	assert addressOf(registry) === "/shop/product/7?__nav.inspector=%2Fmaterials%2Fwood",
		addressOf(registry);
	assert session.navigate("/shop/product/8", false).ok;
	assert inspector.get() === "";
	assert visibleText(app.root).indexOf("product 8") >= 0, visibleText(app.root);
	assert session.navigate("/shop/product/8?__nav.inspector=%2Fmaterials%2Fglass", false).ok;
	assert history.go(-1);
	assert inspector.get() === "";
	assert visibleText(app.root).indexOf("product 8") >= 0, visibleText(app.root);
	assert history.go(-2);
	assert app.ref.currentPath() === "Home", app.ref.currentPath();
	assert errors.length === 0;
	session.dispose();
	app.dispose();
}

test "a container in a secondary scope returns to its initial route when its address is absent" {
	const registry = new RoutingRegistry("main");
	const page = new Signal<string>("");
	registry.register(namedParticipant("main", "/pages/", page));
	const app = startApp(registry, "nav", nothing);
	const errors: RoutingError[] = [];
	const history = createMemoryRoutingHistory({ url: "/pages/a", state: "" });
	const session = open(registry, history, errors);
	assert app.ref.currentPath() === "Home", app.ref.currentPath();
	assert session.navigate("/pages/a?__nav.nav=%2Fshop%2Fproduct%2F42", false).ok;
	assert app.ref.currentPath() === "Shop>Product", app.ref.currentPath();
	const nested = "/pages/a?__nav.nav=%2Fshop%2Fproduct%2F42";
	assert addressOf(registry) === nested, addressOf(registry);
	assert session.navigate("/pages/b", false).ok;
	assert app.ref.currentPath() === "Home", app.ref.currentPath();
	assert page.get() === "b";
	assert addressOf(registry) === "/pages/b?__nav.nav=%2F", addressOf(registry);
	assert errors.length === 0;
	session.dispose();
	app.dispose();
}

test "a captured snapshot restores the nested tree, params included" {
	const registry = new RoutingRegistry("main");
	const app = startApp(registry, "main", nothing);
	assert app.ref.linkTo("/shop/product/42");
	const snapshot = registry.capture();
	assert snapshot.regions.length === 1 && snapshot.regions[0].scope === "main";
	assert app.ref.linkTo("/");
	assert app.ref.currentPath() === "Home", app.ref.currentPath();
	assert registry.restore(snapshot).ok;
	assert app.ref.currentPath() === "Shop>Product", app.ref.currentPath();
	assert visibleText(app.root).indexOf("product 42") >= 0, visibleText(app.root);
	assert app.ref.canGoBack(), "the restored stack keeps the catalog below";
	const state: NavigationState = app.ref.getRootState();
	assert state.routes[state.index].name === "Shop";
	app.dispose();
}

test "a snapshot restored before the container mounts seeds the nested tree" {
	const first = new RoutingRegistry("main");
	const before = startApp(first, "main", nothing);
	assert before.ref.linkTo("/shop/product/9");
	const snapshot = first.capture();
	before.dispose();
	const registry = new RoutingRegistry("main");
	let restored = false;
	let early = "";
	const app = startApp(registry, "main", (): void => {
		restored = registry.restore(snapshot).ok;
		early = addressOf(registry);
	});
	assert restored;
	assert early === "/shop/product/9", early;
	assert app.ref.currentPath() === "Shop>Product", app.ref.currentPath();
	assert visibleText(app.root).indexOf("product 9") >= 0, visibleText(app.root);
	assert app.ref.canGoBack();
	app.dispose();
}

test "a malformed or empty snapshot is refused before anything changes" {
	const registry = new RoutingRegistry("main");
	const app = startApp(registry, "main", nothing);
	assert app.ref.linkTo("/shop/product/3");
	const text = registry.restore({ regions: [{ scope: "main", state: "not json" }] });
	assert !text.ok;
	if (!text.ok) { assert text.error === RoutingError.IncompleteSnapshot; }
	const empty = registry.restore({ regions: [{ scope: "main", state: "{\"nodes\":[]}" }] });
	assert !empty.ok;
	if (!empty.ok) { assert empty.error === RoutingError.IncompleteSnapshot; }
	assert app.ref.currentPath() === "Shop>Product", app.ref.currentPath();
	app.dispose();
}

test "an address no screen matches is reported as NoMatch and changes nothing" {
	const registry = new RoutingRegistry("main");
	const errors: RoutingError[] = [];
	let early = true;
	const app = startApp(registry, "main", (): void => {
		const created = createRoutingSession(
			registry,
			createRequestRoutingHistory("/nowhere"),
			(failure: RoutingError): void => { errors.push(failure); },
		);
		early = created.ok;
		if (!created.ok) { assert created.error === RoutingError.NoMatch; }
	});
	assert !early;
	assert app.ref.currentPath() === "Home", app.ref.currentPath();
	const history = createMemoryRoutingHistory({ url: "/", state: "" });
	const session = open(registry, history, errors);
	const refused = session.navigate("/nowhere", false);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error === RoutingError.NoMatch; }
	assert app.ref.currentPath() === "Home", app.ref.currentPath();
	assert history.read().url === "/";
	history.push({ url: "/nowhere", state: "" });
	assert history.go(-1);
	assert errors.length === 0;
	assert history.go(1);
	assert errors.length === 1 && errors[0] === RoutingError.NoMatch;
	assert history.read().url === "/";
	session.dispose();
	app.dispose();
}

test "a path the config maps but no navigator serves fails loudly when it commits" {
	const registry = new RoutingRegistry("main");
	const app = startApp(registry, "main", nothing);
	let message = "";
	try {
		registry.apply("/ghost");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "routing: no navigator has a screen for '/ghost'", message;
	assert app.ref.currentPath() === "Home", app.ref.currentPath();
	app.dispose();
}

test "routing without a linking config throws and registers nothing" {
	const registry = new RoutingRegistry("main");
	let message = "";
	try {
		render(<NavigationContainer routing={{ registry, scope: "main" }}>
			{shell()}
		</NavigationContainer>, mockHost(), mockNode("root") as unknown as HostNode);
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "NavigationContainer: routing needs a linking config", message;
	const prepared = registry.prepare("/");
	assert !prepared.ok;
	if (!prepared.ok) { assert prepared.error === RoutingError.UnknownScope; }
}

test "disposing the container unregisters its scope" {
	const registry = new RoutingRegistry("main");
	const app = startApp(registry, "main", nothing);
	assert registry.prepare("/").ok;
	app.dispose();
	const gone = registry.prepare("/");
	assert !gone.ok;
	if (!gone.ok) { assert gone.error === RoutingError.UnknownScope; }
	const again = startApp(registry, "main", nothing);
	assert registry.prepare("/").ok;
	again.dispose();
}
