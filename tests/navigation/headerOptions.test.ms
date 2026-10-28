import { Dispose } from "../../src/core/types";
import { NeonNode } from "../../src/render/node";
import { Style } from "../../src/render/style";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	NavigationContainer,
	HeaderItemProps,
	HeaderTitleProps,
	ScreenProps,
	NavigationContainerRef,
	createNavigationContainerRef,
	createStackNavigator,
} from "../../src/navigation/index";
import { visibleText } from "./navHarness";

interface NavParams {
	Base: null;
	Detail: null;
}

const Stack = createStackNavigator<NavParams>();

function Plain(props: ScreenProps<NavParams>): NeonNode {
	return <Text>{props.route.name}</Text>;
}

function mount(root: MockNode, ref: NavigationContainerRef): Dispose {
	return render(<NavigationContainer ref={ref}>
		<Stack.Navigator>
			<Stack.Screen name="Base" component={Plain} options={{
				headerTintColor: "#123456",
				headerLeft: (p: HeaderItemProps): NeonNode => <Text>{"L " + p.canGoBack.toString() + " " + p.tintColor}</Text>,
				headerRight: (p: HeaderItemProps): NeonNode => <Text>{"R " + p.tintColor}</Text>,
				headerTitle: (p: HeaderTitleProps): NeonNode => <Text>{"* " + p.children}</Text>,
			}} />
			<Stack.Screen name="Detail" component={Plain} options={{
				headerLeft: (p: HeaderItemProps): NeonNode => <Text>{"L " + p.canGoBack.toString()}</Text>,
				headerBackVisible: true,
				contentStyle: { backgroundColor: "#abcdef" },
			}} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
}

function hasBackground(node: MockNode, color: string): boolean {
	const style = node.style;
	if (style !== null && (style as Style).backgroundColor === color) { return true; }
	for (const child of node.children) {
		if (hasBackground(child, color)) { return true; }
	}
	return false;
}

test "header options given as functions receive the tint and whether the stack can go back" {
	const root: MockNode = mockNode("root");
	const dispose: Dispose = mount(root, createNavigationContainerRef());
	assert visibleText(root) === "L false #123456|* Base|R #123456|Base", visibleText(root);
	dispose();
}

test "headerBackVisible shows the back button beside headerLeft, and contentStyle styles the screen body" {
	const root: MockNode = mockNode("root");
	const ref = createNavigationContainerRef();
	const dispose: Dispose = mount(root, ref);
	assert !hasBackground(root, "#abcdef");
	ref.navigate("Detail");
	assert visibleText(root).indexOf("‹ ") >= 0, visibleText(root);
	assert visibleText(root).indexOf("L true") >= 0, visibleText(root);
	assert hasBackground(root, "#abcdef");
	dispose();
}
