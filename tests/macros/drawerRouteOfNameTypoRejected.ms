import { NeonNode } from "../../src/render/node";
import { Text } from "../../src/components/primitives";
import { ScreenProps, createDrawerNavigator } from "../../src/navigation/index";

interface Drawers {
	Home: null;
	Account: { id: string };
}

export const Drawer = createDrawerNavigator<Drawers>();

export function Home(props: ScreenProps<Drawers>): NeonNode {
	props.navigation.reset({ routes: [props.navigation.routeOf("Accoun", { id: "a" })] });
	return <Text>home</Text>;
}
