import { NeonNode } from "../../src/render/node";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	Navigation,
	NavigationContainer,
	ScreenProps,
	createBottomTabNavigator,
	createStackNavigator,
} from "../../src/navigation/index";

interface TabList {
	Main: null;
	Other: null;
}

interface StackList {
	Leaf: null;
}

const Tab = createBottomTabNavigator<TabList>();
const Stack = createStackNavigator<StackList>();

let leaf: Navigation<StackList> | null = null;

function Leaf(props: ScreenProps<StackList>): NeonNode {
	leaf = props.navigation;
	return <Text>leaf</Text>;
}

function Main(props: ScreenProps<TabList>): NeonNode {
	return <Stack.Navigator id="inner">
		<Stack.Screen name="Leaf" component={Leaf} />
	</Stack.Navigator>;
}

function Other(props: ScreenProps<TabList>): NeonNode {
	return <Text>other</Text>;
}

function mount(): void {
	const root = mockNode("root");
	render(<NavigationContainer>
		<Tab.Navigator id="tabs">
			<Tab.Screen name="Main" component={Main} />
			<Tab.Screen name="Other" component={Other} />
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
}

test "getParent with an id reaches the closest navigator that carries it" {
	mount();
	const tabs = (leaf as Navigation<StackList>).getParent<StackList, TabList>("tabs");
	assert tabs.route.name === "Main", tabs.route.name;
}

test "getParent with the id of the screen's own navigator returns the screen's navigation" {
	mount();
	const own = (leaf as Navigation<StackList>).getParent<StackList, StackList>("inner");
	assert own.route.name === "Leaf", own.route.name;
}

test "getParent with an id no navigator carries fails loud" {
	mount();
	let message = "";
	try {
		(leaf as Navigation<StackList>).getParent<StackList, TabList>("missing");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "getParent: no navigator with id 'missing' contains 'Leaf'", message;
}
