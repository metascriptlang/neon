import { NeonNode } from "../../../src/render/node";
import { View, Text } from "../../../src/components/primitives";
import { runApp } from "../../../src/platform/native/host";

function App(): NeonNode {
	return <View><Text>hi</Text></View>;
}

runApp(App);
