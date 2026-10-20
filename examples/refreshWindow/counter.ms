import { createSignal } from "../../src/core/signal";
import { NeonEvent } from "../../src/render/event";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { View, Text, Pressable, TextInput } from "../../src/components/primitives";

const styles = createStyles({
	root: { flex: 1 },
	title: { position: "absolute", left: 24, top: 24, color: "#cdd6f4", fontSize: 20 },
	value: { position: "absolute", left: 24, top: 64, color: "#89b4fa", fontSize: 28 },
	button: { position: "absolute", left: 24, top: 120, width: 160, height: 48, backgroundColor: "#313244" },
	label: { color: "#cdd6f4", fontSize: 16, padding: 12 },
	field: { position: "absolute", left: 24, top: 200, width: 240, height: 36, color: "#cdd6f4", backgroundColor: "#45475a", fontSize: 16 },
});

export function Counter(): NeonNode {
	const [count, setCount] = createSignal(0);
	const inc: (e: NeonEvent) => void = () => {
		const n = count() + 1;
		setCount(n);
		console.log("RW press count=" + n.toString());
	};
	return <View style={styles.root} onLayout={(e: NeonEvent): void => { console.log("RW layout"); }}>
		<Text style={styles.title}>Counter v1</Text>
		<Text style={styles.value}>{"count " + count().toString()}</Text>
		<Pressable style={styles.button} onPress={inc}><Text style={styles.label}>tap</Text></Pressable>
		<TextInput style={styles.field} onChangeText={(t: string): void => { console.log("RW text \"" + t + "\""); }} />
	</View>;
}
