import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	NavigationContainer,
	NavigationContainerRef,
	NavigationHistoryItem,
	NavigationState,
	ScreenProps,
	createBottomTabNavigator,
	createDrawerNavigator,
	createNavigationContainerRef,
} from "../../src/navigation/index";
import { findLabel, settle } from "./navHarness";

interface NavParams {
	A: null;
	B: null;
	C: null;
}

const Tab = createBottomTabNavigator<NavParams>();
const Drawer = createDrawerNavigator<NavParams>();

function Plain(props: ScreenProps<NavParams>): NeonNode {
	return <Text>plain</Text>;
}

function mountTabs(ref: NavigationContainerRef, initial: NavigationState | null): MockNode {
	const root = mockNode("root");
	render(<NavigationContainer ref={ref} initialState={initial}>
		<Tab.Navigator backBehavior="history">
			<Tab.Screen name="A" component={Plain} />
			<Tab.Screen name="B" component={Plain} />
			<Tab.Screen name="C" component={Plain} />
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	return root;
}

function mountDrawer(ref: NavigationContainerRef, initial: NavigationState | null): MockNode {
	const root = mockNode("root");
	render(<NavigationContainer ref={ref} initialState={initial}>
		<Drawer.Navigator>
			<Drawer.Screen name="A" component={Plain} />
			<Drawer.Screen name="B" component={Plain} />
		</Drawer.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	return root;
}

function keysOf(state: NavigationState): string {
	let out = "";
	const history = state.history;
	if (history === null) { return "none"; }
	for (const item of history as NavigationHistoryItem[]) {
		out += item.type === "route" ? (item.key as string) : "drawer:" + (item.status as string);
		out += ";";
	}
	return out;
}

test "a tab navigator's persisted state lists the visited routes" {
	const ref = createNavigationContainerRef();
	mountTabs(ref, null);
	ref.navigate("B");
	ref.navigate("C");
	const state = ref.getRootState();
	const names: string[] = [];
	for (const item of state.history as NavigationHistoryItem[]) {
		for (const route of state.routes) {
			if (item.key === route.key) { names.push(route.name); }
		}
	}
	assert names.join(",") === "A,B,C", names.join(",");
}

test "a saved tab state brings back its visit history for goBack" {
	const first = createNavigationContainerRef();
	mountTabs(first, null);
	first.navigate("B");
	first.navigate("C");
	const saved = first.getRootState();
	const again = createNavigationContainerRef();
	mountTabs(again, saved);
	assert again.currentPath() === "C", again.currentPath();
	again.goBack();
	assert again.currentPath() === "B", again.currentPath();
	again.goBack();
	assert again.currentPath() === "A", again.currentPath();
}

test "an open drawer is part of the persisted state and opens again from it" {
	const first = createNavigationContainerRef();
	mountDrawer(first, null);
	assert keysOf(first.getRootState()).indexOf("drawer") < 0, keysOf(first.getRootState());
	first.openDrawer();
	flush();
	const saved = first.getRootState();
	assert keysOf(saved).indexOf("drawer:open") >= 0, keysOf(saved);
	assert saved.default === "closed", saved.default as string;
	const again = createNavigationContainerRef();
	const root = mountDrawer(again, saved);
	settle();
	assert findLabel(root, "Close navigation menu") !== null, "the restored drawer is open";
}
