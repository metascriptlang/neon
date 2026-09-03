// Counter — the canonical first Neon component: own state, bare JSX, no macro
// call, speaking the universal vocabulary (View/Text/Pressable — hosts translate
// the wire tags; handlers receive a typed NeonEvent since 2026-09-03).

import { createSignal } from "../core/signal";
import { createStyles, styleOf } from "../macros/ui/style";
import { NeonNode } from "../render/node";
import { View, Text, Pressable } from "./rn";

const styles = createStyles({
	container: { flexDirection: "column", alignItems: "center", gap: 12, padding: 24 },
	title: { color: "#cdd6f4", fontSize: 20, fontWeight: "bold" },
	value: { color: "#89b4fa", fontSize: 48, fontWeight: "bold" },
	row: { flexDirection: "row", gap: 12 },
	button: { backgroundColor: "#313244", color: "#cdd6f4", padding: 12, borderRadius: 8, fontSize: 16 },
	hint: { color: "#6c7086", fontSize: 12 },
});

export function Counter(): NeonNode {
	const [count, setCount] = createSignal(0);
	return <View style={styles.container}>
		<Text style={styles.title}>Neon Counter</Text>
		<Text style={styles.value}>{count().toString()}</Text>
		<View style={styles.row}>
			<Pressable style={styles.button} onPress={() => setCount(count() - 1)}>-</Pressable>
			<Pressable style={styles.button} onPress={() => setCount(0)}>reset</Pressable>
			<Pressable style={styles.button} onPress={() => setCount(count() + 1)}>+</Pressable>
		</View>
		<Text style={styles.hint}>{count() % 2 === 0 ? "even" : "odd"}</Text>
	</View>;
}
