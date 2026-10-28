import { NeonNode } from "../../src/render/node";
import { Text } from "../../src/components/primitives";
import { ScreenProps, createBottomTabNavigator } from "../../src/navigation/index";

interface Tabs {
	Home: null;
	Profile: { id: string };
}

export const Tab = createBottomTabNavigator<Tabs>();

export function Home(props: ScreenProps<Tabs>): NeonNode {
	props.navigation.navigate("Profil", { id: "a" });
	return <Text>home</Text>;
}
