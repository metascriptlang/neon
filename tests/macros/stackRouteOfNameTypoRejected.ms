import { NeonNode } from "../../src/render/node";
import { Text } from "../../src/components/primitives";
import { ScreenProps, createStackNavigator } from "../../src/navigation/index";

interface Routes {
	Home: null;
	Profile: { id: string };
}

export const Stack = createStackNavigator<Routes>();

export function Home(props: ScreenProps<Routes>): NeonNode {
	props.navigation.reset({ routes: [props.navigation.routeOf("Profil", { id: "a" })] });
	return <Text>home</Text>;
}
