import { NeonNode } from "../../../src/render/node";
import { View } from "../../../src/components/primitives";
import { Switch } from "../../../src/components/switch";
import { Video } from "../../../src/components/video";
import { runApp } from "../../../src/platform/native/host";
import "../../../src/api/asyncStorage";

function App(): NeonNode {
	return <View><Switch /><Video /></View>;
}

runApp(App);
