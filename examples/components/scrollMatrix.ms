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
	controls: { flexDirection: "row", gap: 8 },
	button: { padding: 12, backgroundColor: "#45475a", color: "#cdd6f4" },
	scroll: { flex: 1, backgroundColor: "#181825" },
	card: { width: 160, height: 120, padding: 12, margin: 4, backgroundColor: "#313244", color: "#cdd6f4" },
});

function cardNumbers(): number[] {
	const cards: number[] = [];
	for (let i = 1; i <= 24; i += 1) { cards.push(i); }
	return cards;
}

export function ScrollMatrix(): NeonNode {
	const [horizontal, setHorizontal] = createSignal(true);
	const [x, setX] = createSignal<number>(0);
	const [y, setY] = createSignal<number>(0);
	const [pressed, setPressed] = createSignal("none");
	const [refreshing, setRefreshing] = createSignal(false);
	const [refreshed, setRefreshed] = createSignal<int32>(0);
	const cards = cardNumbers();
	return <View style={styles.screen}>
		<Text style={styles.title}>Neon scroll matrix</Text>
		<Text style={styles.status}>{"axis " + (horizontal() ? "horizontal" : "vertical")}</Text>
		<Text style={styles.status}>{"x " + Math.round(x()).toString() + " y " + Math.round(y()).toString()}</Text>
		<Text style={styles.status}>{"pressed " + pressed()}</Text>
		<Text style={styles.status}>{(refreshing() ? "refreshing " : "refreshed ") + refreshed().toString()}</Text>
		<View style={styles.controls}>
			<Pressable style={styles.button} onPress={() => setHorizontal(!horizontal())}>toggle axis</Pressable>
		</View>
		<ScrollView style={styles.scroll} horizontal={horizontal()}
			refreshing={refreshing()}
			onRefresh={() => {
				setRefreshing(true);
				setTimeout((): void => {
					setRefreshed(refreshed() + 1);
					setRefreshing(false);
				}, 800);
			}}
			onScroll={(e: NeonEvent): void => { setX(e.x); setY(e.y); }}>
			<For each={cards}>{(card: number): NeonNode =>
				<Pressable style={styles.card} onPress={() => setPressed("card " + card.toString())}>{"card " + card.toString()}</Pressable>}</For>
		</ScrollView>
	</View>;
}
