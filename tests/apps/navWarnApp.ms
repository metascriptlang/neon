import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/hostTypes";
import { render, mockHost, mockNode, HostNode } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	NavigationContainer,
	ScreenProps,
	createNavigationContainerRef,
	createStackNavigator,
} from "../../src/navigation/index";

interface NoParams {
	Home: null;
}

const Stack = createStackNavigator<NoParams>();

function Home(props: ScreenProps<NoParams>): NeonNode {
	return <Text>home</Text>;
}

function main(): void {
	const ref = createNavigationContainerRef();
	render(element(<NavigationContainer ref={ref}>
		<Stack.Navigator>
			<Stack.Screen name="Home" component={Home} />
		</Stack.Navigator>
	</NavigationContainer>), mockHost(), mockNode("root") as unknown as HostNode);
	flush();
	ref.navigate("Nowhere");
	ref.goBack();
	ref.openDrawer();
	flush();
	console.log("still at " + ref.currentPath());
}

main();
