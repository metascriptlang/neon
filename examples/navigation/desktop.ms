import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { Void, View, Text, TextInput, Pressable } from "../../src/components/primitives";
import { dispatchHardwareBackPress } from "../../src/api/backHandler";
import { runWindow, desktopOptions, DesktopOptions } from "../../src/platform/ion/window";
import {
	ScreenProps, NavigationContainer, createStackNavigator,
} from "../../src/navigation/index";
import { exit } from "std/process";

interface Routes { Home: null; Detail: null; }
const Stack = createStackNavigator<Routes>();

function Home(props: ScreenProps<Routes>): NeonNode {
	const nav = props.navigation;
	return <View style={{ padding: 20 }}>
		<Text style={{ color: "#cdd6f4" }}>home</Text>
		<Pressable onPress={(e: NeonEvent): void => { nav.navigate("Detail"); }}><Text style={{ color: "#89b4fa" }}>open detail</Text></Pressable>
	</View>;
}

function Detail(props: ScreenProps<Routes>): NeonNode {
	return <View style={{ padding: 20 }}>
		<Text style={{ color: "#cdd6f4" }}>detail: Escape goes back</Text>
		<TextInput style={{ width: 240, height: 24 }} onKeyUp={(e: NeonEvent): void => { if (e.code === "Escape") { e.stopPropagation(); } }} />
	</View>;
}

function goBackOnEscape(e: NeonEvent): void {
	if (e.code === "Escape") { dispatchHardwareBackPress(); }
}

function App(): NeonNode {
	return <Void style={{ backgroundColor: "#1e1e2e" }}>
		<View style={{ flex: 1 }} focusable onKeyUp={goBackOnEscape}>
			<NavigationContainer>
				<Stack.Navigator initialRouteName="Home">
					<Stack.Screen name="Home" component={Home} />
					<Stack.Screen name="Detail" component={Detail} />
				</Stack.Navigator>
			</NavigationContainer>
		</View>
	</Void>;
}

const opts: DesktopOptions = { ...desktopOptions("Navigation", 480, 320), font: "../void/assets/font.ttf" };
exit(runWindow(opts, App));
