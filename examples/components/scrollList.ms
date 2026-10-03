import { createSignal } from "../../src/core/signal";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { For } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable, ScrollView } from "../../src/components/primitives";

const styles = createStyles({
	screen: { flex: 1, flexDirection: "column", gap: 8, padding: 16 },
	title: { color: "#cdd6f4", fontSize: 20, fontWeight: "bold" },
	status: { color: "#89b4fa", fontSize: 16 },
	scroll: { flex: 1, backgroundColor: "#181825" },
	row: { height: 64, padding: 16, backgroundColor: "#313244", marginBottom: 4 },
});

function rowNumbers(): number[] {
	const rows: number[] = [];
	for (let i = 1; i <= 40; i += 1) { rows.push(i); }
	return rows;
}

export function ScrollList(): NeonNode {
	// Parked: createSignal(0) infers int32 — ~/metascript/.inbox/compiler/2026-10-03-generic-inferred-from-integer-literal-is-int32.md
	const [offset, setOffset] = createSignal<number>(0);
	const [pressed, setPressed] = createSignal("none");
	const rows = rowNumbers();
	return <View style={styles.screen}>
		<Text style={styles.title}>Neon List</Text>
		<Text style={styles.status}>{"offset " + Math.round(offset()).toString()}</Text>
		<Text style={styles.status}>{"pressed " + pressed()}</Text>
		<ScrollView style={styles.scroll} onScroll={(e: NeonEvent): void => { setOffset(e.y); }}>
			<For each={rows}>{(row: number): NeonNode =>
				<Pressable style={styles.row} onPress={() => setPressed("row " + row.toString())}>{"row " + row.toString()}</Pressable>}</For>
		</ScrollView>
	</View>;
}
