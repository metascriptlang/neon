import { createSignal } from "../../../src/core/signal";
import { NeonNode } from "../../../src/render/node";
import { View, Text, Pressable } from "../../../src/components/primitives";

export function Counter(): NeonNode {
	const [count, setCount] = createSignal(0);
	return <View style={{ flexGrow: 1, backgroundColor: "#101820", padding: 20 }}>
		<Pressable style={{ width: 200, height: 60, backgroundColor: "#e63a3a" }} onPress={(): void => {
			const next = count() + 1;
			setCount(next);
			console.log(`HCR count ${next}`);
		}}>
			<Text style={{ color: "#ffffff", fontSize: 24 }}>{"count " + count()}</Text>
		</Pressable>
	</View>;
}
