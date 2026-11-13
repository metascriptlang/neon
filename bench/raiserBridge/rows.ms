import { Accessor } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { For } from "../../src/macros/ui/flow";
import { View, Text, Pressable } from "../../src/components/primitives";

export function range(n: int32): number[] {
	const out: number[] = [];
	for (let i = 0; i < n; i += 1) { out.push(i as number); }
	return out;
}

export function Rows(n: int32, label: Accessor<string>, pressed: () => void): NeonNode {
	return <View style={{ flexDirection: "column" }}>
		<For each={range(n)}>{(item: number, ix: Accessor<number>): NeonNode =>
			<View style={{ flexDirection: "row", height: 20, gap: 4 }}>
				<Text>{label()}</Text>
				<Text>{"row " + item.toString()}</Text>
				<Pressable onPress={pressed}><Text>go</Text></Pressable>
			</View>}
		</For>
	</View>;
}
