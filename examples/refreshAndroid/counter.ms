import { createSignal } from "../../src/core/signal";
import { NeonEvent } from "../../src/render/event";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { View, Text, Pressable } from "../../src/components/primitives";
import { hint } from "./words";

const styles = createStyles({
	container: { flexDirection: "column", alignItems: "center", gap: 12, padding: 24 },
	title: { color: "#cdd6f4", fontSize: 20, fontWeight: "bold" },
	value: { color: "#89b4fa", fontSize: 48, fontWeight: "bold" },
	hint: { color: "#a6adc8", fontSize: 14 },
	button: { backgroundColor: "#313244", color: "#cdd6f4", padding: 12, borderRadius: 8, fontSize: 16 },
});

export function Counter(): NeonNode {
	const [count, setCount] = createSignal(0);
	const inc: (e: NeonEvent) => void = () => { setCount(count() + 1); };
	return <View style={styles.container}>
		<Text style={styles.title}>Counter v1</Text>
		<Text style={styles.value}>{"count " + count().toString()}</Text>
		<Text style={styles.hint}>{hint()}</Text>
		<Pressable style={styles.button} onPress={inc}>tap</Pressable>
	</View>;
}
