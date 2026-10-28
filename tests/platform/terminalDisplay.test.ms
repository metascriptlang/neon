import { flush } from "../../src/core/runtime";
import { createSignal, accessor } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { render } from "../../src/render/host";
import { HostNode } from "../../src/render/hostTypes";
import { Style } from "../../src/render/style";
import { View, Text, Pressable } from "../../src/components/primitives";
import { TerminalNode, createTerminalNode } from "../../src/platform/terminal/types";
import { terminalHost, fireTerminalEvent } from "../../src/platform/terminal/host";
import { paintTree } from "../../src/platform/terminal/paint";
import { ManualFrames, useManualFrames } from "../../src/animation/index";
import {
	ScreenProps, NavigationContainer, createStackNavigator, createBottomTabNavigator,
} from "../../src/navigation/index";

const clock: ManualFrames = useManualFrames();
interface P { Home: null; Detail: null; }
const Stack = createStackNavigator<P>();
const Tabs = createBottomTabNavigator<P>();

function Home(props: ScreenProps<P>): NeonNode {
	const n = props.navigation;
	return <View><Text>home</Text><Pressable onPress={(e: NeonEvent): void => { n.navigate("Detail"); }}><Text>go</Text></Pressable></View>;
}

function Detail(props: ScreenProps<P>): NeonNode {
	return <View><Text>detail</Text></View>;
}

function settle(): void { clock.runAll(); flush(); }
function show(root: TerminalNode): string { return paintTree(root, 60).join("/"); }

function press(n: TerminalNode, label: string): boolean {
	for (const c of n.children) { if (press(c, label)) { return true; } }
	if (paintTree(n, 80).join("|").indexOf(label) < 0) { return false; }
	for (const e of n.events) {
		if (e.name === "onPress") { fireTerminalEvent(n, "onPress"); return true; }
	}
	return false;
}

test "terminal paints only the top screen after a stack push" {
	const root = createTerminalNode("box");
	render(<NavigationContainer>
		<Stack.Navigator initialRouteName="Home">
			<Stack.Screen name="Home" component={Home} />
			<Stack.Screen name="Detail" component={Detail} />
		</Stack.Navigator>
	</NavigationContainer>, terminalHost(), root as unknown as HostNode);
	settle();
	assert show(root).indexOf("home") >= 0, "home paints at the root";
	assert press(root, "go"), "the go button fires";
	settle();
	const shown = show(root);
	assert shown.indexOf("detail") >= 0, "detail paints after the push";
	assert shown.indexOf("home") < 0, "home is not painted under detail";
}

test "terminal paints only the active tab after a switch" {
	const root = createTerminalNode("box");
	render(<NavigationContainer>
		<Tabs.Navigator>
			<Tabs.Screen name="Home" component={Home} />
			<Tabs.Screen name="Detail" component={Detail} />
		</Tabs.Navigator>
	</NavigationContainer>, terminalHost(), root as unknown as HostNode);
	settle();
	const first = show(root);
	assert first.indexOf("home") >= 0, "the first tab paints";
	assert first.indexOf("detail") < 0, "the inactive tab is not painted";
	assert press(root, "Detail"), "the Detail tab button fires";
	settle();
	const second = show(root);
	assert second.indexOf("detail") >= 0, "the chosen tab paints";
	assert second.indexOf("home") < 0, "the left tab is not painted";
}

test "terminal display none hides a view with its descendants and flex shows it again" {
	const [shown, setShown] = createSignal<boolean>(false);
	const root = createTerminalNode("box");
	const frame = accessor((): Style => ({ display: shown() ? "flex" : "none" }));
	render(<View><Text>before</Text><View style={frame}><Text>inner</Text></View><Text>after</Text></View>,
		terminalHost(), root as unknown as HostNode);
	flush();
	assert show(root) === "before/after", "display none paints nothing for the view";
	setShown(true);
	flush();
	assert show(root) === "before/inner/after", "display flex paints the view again";
	setShown(false);
	flush();
	assert show(root) === "before/after", "display none hides it once more";
}

test "terminal row gives a hidden child no column" {
	const host = terminalHost();
	const row = createTerminalNode("row");
	const a = createTerminalNode("box");
	const b = createTerminalNode("box");
	const c = createTerminalNode("box");
	host.append(row as unknown as HostNode, a as unknown as HostNode);
	host.append(row as unknown as HostNode, b as unknown as HostNode);
	host.append(row as unknown as HostNode, c as unknown as HostNode);
	host.append(a as unknown as HostNode, host.createText("A"));
	host.append(b as unknown as HostNode, host.createText("B"));
	host.append(c as unknown as HostNode, host.createText("C"));
	host.setStyle(b as unknown as HostNode, { display: "none" } as Style);
	const lines = paintTree(row, 10);
	assert lines.length === 1 && lines[0] === "A    C    ", "two visible children share the width: " + lines.join("/");
}
