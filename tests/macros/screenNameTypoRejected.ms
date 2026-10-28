import { NeonNode } from "../../src/render/hostTypes";
import { Text } from "../../src/components/primitives";
import { ScreenProps, createStackNavigator } from "../../src/navigation/index";

interface Routes {
	Home: null;
}

const Stack = createStackNavigator<Routes>();

function Home(props: ScreenProps<Routes>): NeonNode {
	return <Text>home</Text>;
}

export function app(): NeonNode {
	return <Stack.Navigator>
		<Stack.Screen name="Hmoe" component={Home} />
	</Stack.Navigator>;
}
