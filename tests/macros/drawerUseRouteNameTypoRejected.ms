import { NeonNode } from "../../src/render/node";
import { Text } from "../../src/components/primitives";
import { ScreenProps, createDrawerNavigator, useRoute } from "../../src/navigation/index";

interface Drawers {
	Home: null;
	Account: { id: string };
}

export const Drawer = createDrawerNavigator<Drawers>();

export function Home(props: ScreenProps<Drawers>): NeonNode {
	const route = useRoute<Drawers, "Accoun">();
	return <Text>home</Text>;
}
