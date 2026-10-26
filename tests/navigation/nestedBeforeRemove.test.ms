import { flush } from "../../src/core/runtime";
import { createSignal } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { Dispose } from "../../src/core/types";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	Navigation,
	NavigationContainer,
	NavigationContainerRef,
	NavigationEventArg,
	ScreenProps,
	createNavigationContainerRef,
	createStackNavigator,
} from "../../src/navigation/index";
import { settle } from "./navHarness";

interface OuterParams {
	Home: null;
	Editor: null;
	Other: null;
}

interface InnerParams {
	Intro: null;
	Form: null;
}

const Outer = createStackNavigator<OuterParams>();
const Inner = createStackNavigator<InnerParams>();

let outerNavigation: Navigation<OuterParams> | null = null;
let asked = "";
let dirty = true;

function Home(props: ScreenProps<OuterParams>): NeonNode {
	outerNavigation = props.navigation;
	return <Text>home</Text>;
}

function Other(props: ScreenProps<OuterParams>): NeonNode {
	return <Text>other</Text>;
}

function Intro(props: ScreenProps<InnerParams>): NeonNode {
	const stop = props.navigation.addListener("beforeRemove", (e: NavigationEventArg): void => {
		asked += "intro;";
	});
	onCleanup(stop);
	return <Text>intro</Text>;
}

function Form(props: ScreenProps<InnerParams>): NeonNode {
	const stop = props.navigation.addListener("beforeRemove", (e: NavigationEventArg): void => {
		asked += "form;";
		if (dirty) { e.preventDefault(); }
	});
	onCleanup(stop);
	return <Text>form</Text>;
}

function Editor(props: ScreenProps<OuterParams>): NeonNode {
	outerNavigation = props.navigation;
	return <Inner.Navigator initialRouteName="Intro">
		<Inner.Screen name="Intro" component={Intro} />
		<Inner.Screen name="Form" component={Form} />
	</Inner.Navigator>;
}

let unmount: Dispose | null = null;

function mountApp(ref: NavigationContainerRef): void {
	if (unmount !== null) { (unmount as Dispose)(); }
	const root: MockNode = mockNode("root");
	unmount = render(<NavigationContainer ref={ref}>
		<Outer.Navigator initialRouteName="Home">
			<Outer.Screen name="Home" component={Home} />
			<Outer.Screen name="Editor" component={Editor} />
			<Outer.Screen name="Other" component={Other} />
		</Outer.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	flush();
	settle();
}

function openForm(ref: NavigationContainerRef): void {
	asked = "";
	dirty = true;
	ref.navigate("Editor");
	flush();
	ref.navigate("Form");
	flush();
	settle();
}

test "removing a parent route asks the beforeRemove listeners of its nested screens, deepest first" {
	const ref = createNavigationContainerRef();
	mountApp(ref);
	openForm(ref);
	assert ref.currentPath() === "Editor>Form", ref.currentPath();
	(outerNavigation as Navigation<OuterParams>).goBack();
	flush();
	assert asked === "form;", asked;
	assert ref.currentPath() === "Editor>Form", "the nested guard kept the parent route: " + ref.currentPath();
}

test "a nested guard that agrees lets the parent route go after every nested screen was asked" {
	const ref = createNavigationContainerRef();
	mountApp(ref);
	openForm(ref);
	dirty = false;
	(outerNavigation as Navigation<OuterParams>).goBack();
	flush();
	settle();
	assert asked === "form;intro;", asked;
	assert ref.currentPath() === "Home", ref.currentPath();
}

test "replacing the parent route is guarded by its nested screens too" {
	const ref = createNavigationContainerRef();
	mountApp(ref);
	openForm(ref);
	(outerNavigation as Navigation<OuterParams>).replace("Other");
	flush();
	assert ref.currentPath() === "Editor>Form", ref.currentPath();
}
