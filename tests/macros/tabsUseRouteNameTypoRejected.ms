import { NeonNode } from "../../src/render/node";
import { Text } from "../../src/components/primitives";
import { ScreenProps, createBottomTabNavigator, useRoute } from "../../src/navigation/index";

interface Tabs {
	Home: null;
	Profile: { id: string };
}

export const Tab = createBottomTabNavigator<Tabs>();

export function Home(props: ScreenProps<Tabs>): NeonNode {
	const route = useRoute<Tabs, "Profil">();
	return <Text>home</Text>;
}
