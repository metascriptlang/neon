import { runApp } from "../../../src/platform/native/host";
import { createSignal, Accessor } from "../../../src/core/signal";
import { For } from "../../../src/macros/ui/flow";
import { View, Text, Pressable } from "../../../src/components/primitives";
import { NeonNode, Host, HostNode } from "../../../src/render/host";
import { element } from "../../../src/macros/ui/element";

const CYCLES = 20000;

function churn(): NeonNode {
	const [rows, setRows] = createSignal<number[]>([]);
	const [status, setStatus] = createSignal("churning");
	const tree = element(<View>
		<Text>{status()}</Text>
		<For each={rows()}>{(row: number, i: Accessor<number>): NeonNode =>
			<Pressable onPress={() => { setStatus("pressed " + row.toString()); }}>row</Pressable>}</For>
	</View>);
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		tree(host, parent, before);
		for (let cycle = 0; cycle < CYCLES; cycle += 1) {
			setRows([1, 2, 3]);
			setRows([]);
		}
		setStatus("churned " + CYCLES.toString());
	};
}

runApp(churn);
