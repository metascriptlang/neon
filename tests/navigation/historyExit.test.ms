import { createRoot } from "../../src/core/owner";
import { Dispose } from "../../src/core/types";
import { NeonNode } from "../../src/render/node";
import { Style } from "../../src/render/style";
import { HostNode, MockNode, mockHost, mockNode } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	LinkingOptions,
	NavigationContainer,
	RoutingError,
	RoutingRegistry,
	RoutingSession,
	ScreenProps,
	createMemoryRoutingHistory,
	createNavigationContainerRef,
	createRoutingSession,
	createStackNavigator,
} from "../../src/navigation/index";
import { clock, settle } from "./navHarness";

interface NavParams {
	Home: null;
	Detail: null;
}

const Stack = createStackNavigator<NavParams>();

const linking: LinkingOptions = {
	prefixes: [],
	enabled: false,
	config: {
		screens: [{ name: "Home", path: "" }, { name: "Detail", path: "detail" }],
	},
};

function Home(props: ScreenProps<NavParams>): NeonNode {
	return <Text>home</Text>;
}

function Detail(props: ScreenProps<NavParams>): NeonNode {
	return <Text>detail</Text>;
}

function texts(node: MockNode, prefix: string): int32 {
	if (node.tag === "") { return node.text.startsWith(prefix) ? 1 : 0; }
	let count: int32 = 0;
	for (const child of node.children) { count += texts(child, prefix); }
	return count;
}

function sliding(node: MockNode, prefix: string): boolean {
	const style = node.style;
	if (style !== null && (style as Style).transform !== null && texts(node, prefix) > 0) {
		return true;
	}
	for (const child of node.children) {
		if (sliding(child, prefix)) { return true; }
	}
	return false;
}

test "browser forward during a pop's exit slides the screen back in, and its next pop slides out" {
	const registry = new RoutingRegistry("main");
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const memory = createMemoryRoutingHistory({ url: "/", state: "" });
	const errors: RoutingError[] = [];
	let opened: RoutingSession | null = null;
	const dispose = createRoot((stop: Dispose): Dispose => {
		const container = NavigationContainer({
			children: <Stack.Navigator>
				<Stack.Screen name="Home" component={Home} />
				<Stack.Screen name="Detail" component={Detail} />
			</Stack.Navigator>,
			linking,
			ref,
			routing: { registry, scope: "main" },
		});
		const created = createRoutingSession(
			registry,
			memory,
			(failure: RoutingError): void => { errors.push(failure); },
		);
		if (!created.ok) { throw new Error("session: " + created.error.toString()); }
		opened = created.value;
		container(mockHost(), root as unknown as HostNode, null);
		return stop;
	});
	const session = opened as RoutingSession;
	const stop = ref.enableHistory(session);
	ref.navigate("Detail");
	settle();
	assert memory.go(-1);
	clock.step(4);
	assert sliding(root, "detail"), "the popped screen slides out";
	assert memory.go(1);
	assert ref.currentPath() === "Detail", ref.currentPath();
	assert texts(root, "detail") === 1, "one Detail: " + texts(root, "detail").toString();
	clock.step(4);
	assert sliding(root, "detail"), "the restored screen slides in";
	settle();
	assert !sliding(root, "detail"), "the restored screen settles";
	ref.goBack();
	clock.step(4);
	assert sliding(root, "detail"), "the restored screen slides out on its pop";
	settle();
	assert texts(root, "detail") === 0, "Detail is gone once it is out";
	stop();
	session.dispose();
	dispose();
	assert errors.length === 0, "routing errors";
}
