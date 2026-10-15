import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { HostNode, mockHost, mockNode, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	Navigation,
	NavigationContainer,
	ScreenProps,
	createDrawerNavigator,
	createNavigationContainerRef,
} from "../../src/navigation/index";
import { findLabel } from "./navHarness";

const Drawer = createDrawerNavigator<string>();

let leaving: Navigation<string> | null = null;

function Plain(props: ScreenProps<string>): NeonNode {
	return <Text>plain</Text>;
}

function Remembered(props: ScreenProps<string>): NeonNode {
	leaving = props.navigation;
	return <Text>remembered</Text>;
}

test "two drawer toggles in one flush leave the drawer closed" {
	leaving = null;
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Drawer.Navigator screenOptions={{ lazy: false }}>
			<Drawer.Screen name="Home" component={Remembered} />
			<Drawer.Screen name="Other" component={Plain} />
		</Drawer.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	const home = leaving as Navigation<string>;
	flush((): void => {
		home.toggleDrawer();
		home.toggleDrawer();
	});
	assert findLabel(root, "Close navigation menu") === null, "the drawer ended open";
	home.toggleDrawer();
	assert findLabel(root, "Close navigation menu") !== null, "a single toggle opens the drawer";
	dispose();
}
