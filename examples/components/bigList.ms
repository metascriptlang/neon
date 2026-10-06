import { createSignal } from "../../src/core/signal";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable } from "../../src/components/primitives";
import { FlatList, FlatListHandle, ItemLayout, ListRenderItemInfo } from "../../src/components/flatList";

const ROW = 68;
const COUNT = 10000;

const styles = createStyles({
	screen: { flex: 1, flexDirection: "column", gap: 8, padding: 16 },
	title: { color: "#cdd6f4", fontSize: 20, fontWeight: "bold" },
	status: { color: "#89b4fa", fontSize: 16 },
	jump: { backgroundColor: "#45475a", color: "#cdd6f4", padding: 8, borderRadius: 6 },
	list: { flex: 1, backgroundColor: "#181825" },
	row: { height: 64, padding: 16, backgroundColor: "#313244", marginBottom: 4 },
});

interface Entry {
	id: string;
	n: number;
}

function entries(): Entry[] {
	const out: Entry[] = [];
	for (let i = 0; i < COUNT; i += 1) { out.push({ id: "e" + i.toString(), n: i }); }
	return out;
}

function rowLayout(data: Entry[], index: number): ItemLayout {
	return { length: ROW, offset: ROW * index, index };
}

export function BigList(): NeonNode {
	const started = performance.now();
	const [mounted, setMounted] = createSignal<number>(-1);
	// Parked: createSignal(0) infers int32 — ~/metascript/.inbox/compiler/2026-10-03-generic-inferred-from-integer-literal-is-int32.md
	const [offset, setOffset] = createSignal<number>(0);
	const [pressed, setPressed] = createSignal("none");
	const data = entries();
	const handles: FlatListHandle[] = [];
	return <View style={styles.screen}>
		<Text style={styles.title}>Neon FlatList</Text>
		<Text style={styles.status}>{mounted() < 0 ? "mounting" : "mounted " + Math.round(mounted()).toString() + " ms"}</Text>
		<Text style={styles.status}>{"offset " + Math.round(offset()).toString()}</Text>
		<Text style={styles.status}>{"pressed " + pressed()}</Text>
		<Pressable style={styles.jump} onPress={() => handles[0].scrollToIndex({ index: 5000, animated: false })}>jump 5000</Pressable>
		<FlatList data={data} style={styles.list} getItemLayout={rowLayout}
			ref={(h: FlatListHandle): void => { handles.push(h); }}
			onScroll={(e: NeonEvent): void => { setOffset(e.y); }}
			onLayout={(e: NeonEvent): void => { if (mounted() < 0) { setMounted(performance.now() - started); } }}
			renderItem={(info: ListRenderItemInfo<Entry>): NeonNode =>
				<Pressable style={styles.row} onPress={() => setPressed("row " + info.item.n.toString())}
					onLongPress={() => setPressed("long row " + info.item.n.toString())}>{"row " + info.item.n.toString()}</Pressable>} />
	</View>;
}
