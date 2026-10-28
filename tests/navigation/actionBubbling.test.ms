import { flush } from "../../src/core/runtime";
import { Dispose } from "../../src/core/types";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	Navigation,
	NavigationContainer,
	NavigationContainerRef,
	ScreenProps,
	createNavigationContainerRef,
	createStackNavigator,
} from "../../src/navigation/index";
import { settle } from "./navHarness";

interface OuterParams {
	Home: null;
	Middle: null;
	Editor: null;
	Other: null;
}

interface InnerParams {
	Intro: null;
	Form: null;
	Other: null;
	Nowhere: null;
}

const Outer = createStackNavigator<OuterParams>();
const Inner = createStackNavigator<InnerParams>();

let innerNavigation: Navigation<InnerParams> | null = null;

function Plain(props: ScreenProps<OuterParams>): NeonNode {
	return <Text>{props.route.name}</Text>;
}

function Intro(props: ScreenProps<InnerParams>): NeonNode {
	innerNavigation = props.navigation;
	return <Text>intro</Text>;
}

function Form(props: ScreenProps<InnerParams>): NeonNode {
	return <Text>form</Text>;
}

function Editor(props: ScreenProps<OuterParams>): NeonNode {
	return <Inner.Navigator initialRouteName="Intro">
		<Inner.Screen name="Intro" component={Intro} />
		<Inner.Screen name="Form" component={Form} />
	</Inner.Navigator>;
}

let unmount: Dispose | null = null;

function mountEditor(ref: NavigationContainerRef): void {
	if (unmount !== null) { (unmount as Dispose)(); }
	const root: MockNode = mockNode("root");
	unmount = render(<NavigationContainer ref={ref}>
		<Outer.Navigator initialRouteName="Home">
			<Outer.Screen name="Home" component={Plain} />
			<Outer.Screen name="Middle" component={Plain} />
			<Outer.Screen name="Editor" component={Editor} />
			<Outer.Screen name="Other" component={Plain} />
		</Outer.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	flush();
	ref.navigate("Middle");
	flush();
	ref.navigate("Editor");
	flush();
	settle();
}

test "pop at a nested stack's root pops the parent route that hosts it" {
	const ref = createNavigationContainerRef();
	mountEditor(ref);
	assert ref.currentPath() === "Editor>Intro", ref.currentPath();
	(innerNavigation as Navigation<InnerParams>).pop();
	flush();
	assert ref.currentPath() === "Middle", ref.currentPath();
}

test "popToTop at a nested stack's root pops the parent stack to its top" {
	const ref = createNavigationContainerRef();
	mountEditor(ref);
	(innerNavigation as Navigation<InnerParams>).popToTop();
	flush();
	assert ref.currentPath() === "Home", ref.currentPath();
}

test "pop with a nested stack above its root stays inside the nested stack" {
	const ref = createNavigationContainerRef();
	mountEditor(ref);
	(innerNavigation as Navigation<InnerParams>).navigate("Form");
	flush();
	assert ref.currentPath() === "Editor>Form", ref.currentPath();
	(innerNavigation as Navigation<InnerParams>).pop();
	flush();
	assert ref.currentPath() === "Editor>Intro", ref.currentPath();
}

test "replace with a name only the parent navigator has replaces the parent route" {
	const ref = createNavigationContainerRef();
	mountEditor(ref);
	(innerNavigation as Navigation<InnerParams>).replace("Other");
	flush();
	assert ref.currentPath() === "Other", ref.currentPath();
}

test "replace with a name no navigator has throws and names the action" {
	const ref = createNavigationContainerRef();
	mountEditor(ref);
	let message = "";
	try {
		(innerNavigation as Navigation<InnerParams>).replace("Nowhere");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message.indexOf("REPLACE") >= 0 && message.indexOf("Nowhere") >= 0, message;
}
