import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { Style } from "../../src/render/style";
import { HostNode, MockNode, mockHost, mockNode, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	DRAWER_WIDTH,
	NavigationContainer,
	ScreenProps,
	createDrawerNavigator,
	createNavigationContainerRef,
} from "../../src/navigation/index";
import { findLabel, settle } from "./navHarness";

interface NavParams {
	Home: null;
	Other: null;
}

const Drawer = createDrawerNavigator<NavParams>();

function Plain(props: ScreenProps<NavParams>): NeonNode {
	return <Text>plain</Text>;
}

function styled(node: MockNode, test: (style: Style) => boolean): boolean {
	const style = node.style;
	if (style !== null && test(style as Style)) { return true; }
	for (const child of node.children) {
		if (styled(child, test)) { return true; }
	}
	return false;
}

test "defaultStatus open mounts the drawer open" {
	const root = mockNode("root");
	const dispose = render(<NavigationContainer>
		<Drawer.Navigator defaultStatus="open">
			<Drawer.Screen name="Home" component={Plain} />
			<Drawer.Screen name="Other" component={Plain} />
		</Drawer.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	settle();
	assert findLabel(root, "Close navigation menu") !== null, "open from the first render";
	dispose();
}

test "overlayColor colors the backdrop of the focused screen's drawer" {
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Drawer.Navigator>
			<Drawer.Screen name="Home" component={Plain} options={{ overlayColor: "#112233" }} />
			<Drawer.Screen name="Other" component={Plain} />
		</Drawer.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	ref.openDrawer();
	flush();
	const backdrop = findLabel(root, "Close navigation menu");
	assert backdrop !== null;
	assert ((backdrop as MockNode).style as Style).backgroundColor === "#112233";
	dispose();
}

test "swipeEdgeWidth sets the width of the edge that opens the drawer" {
	const root = mockNode("root");
	const dispose = render(<NavigationContainer>
		<Drawer.Navigator>
			<Drawer.Screen name="Home" component={Plain} options={{ swipeEdgeWidth: 40 }} />
			<Drawer.Screen name="Other" component={Plain} />
		</Drawer.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	settle();
	assert styled(root, (s: Style): boolean => s.position === "absolute" && s.width === 40);
	dispose();
}

test "drawerType slide moves the screens with the drawer, front leaves them still" {
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Drawer.Navigator>
			<Drawer.Screen name="Home" component={Plain} options={{ drawerType: "slide" }} />
			<Drawer.Screen name="Other" component={Plain} options={{ drawerType: "front" }} />
		</Drawer.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	const moved = "translateX(" + DRAWER_WIDTH.toString() + "px)";
	ref.openDrawer();
	flush();
	settle();
	assert styled(root, (s: Style): boolean => s.transform === moved), "slide moves the content";
	ref.navigate("Other");
	settle();
	ref.openDrawer();
	flush();
	settle();
	assert !styled(root, (s: Style): boolean => s.transform === moved), "front keeps the content in place";
	dispose();
}
