// S1 "scroll while data streams in": 2000 cards; every 200 ms, 20 cards change and 2 are appended,
// from a seeded generator, so every host and every run sees the same updates.
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { View, Text } from "../../src/components/primitives";
import { FlatList, ItemLayout, ListRenderItemInfo } from "../../src/components/flatList";

const CARD = 72;
const START = 2000;
const CHANGED = 20;
const APPENDED = 2;
const PERIOD_MS = 200;

interface Card {
	id: string;
	title: string;
	value: number;
}

let seed: int64 = 12345;
function next(): int32 {
	seed = (seed * 1103515245 + 12345) % 2147483648;
	return seed as int32;
}

function card(n: number, value: number): Card {
	return { id: "c" + n.toString(), title: "Card " + n.toString(), value };
}

function initial(): Card[] {
	const out: Card[] = [];
	for (let i = 0; i < START; i += 1) { out.push(card(i, next() % 1000)); }
	return out;
}

function cardLayout(data: Card[], index: number): ItemLayout {
	return { length: CARD, offset: CARD * index, index };
}

export function Stream(): NeonNode {
	const [cards, setCards] = createSignal<Card[]>(initial());
	const [ticks, setTicks] = createSignal<number>(0);
	setInterval((): void => {
		const was = cards();
		const out = was.slice();
		for (let i = 0; i < CHANGED; i += 1) {
			const at = next() % out.length;
			out[at] = card(at, next() % 1000);
		}
		for (let i = 0; i < APPENDED; i += 1) { out.push(card(out.length, next() % 1000)); }
		setCards(out);
		setTicks(ticks() + 1);
	}, PERIOD_MS);
	return <View style={{ flex: 1, backgroundColor: "#1e1e2e" }}>
		<Text style={{ color: "#a6adc8", fontSize: 14, padding: 8 }}>{"ticks " + ticks().toString()}</Text>
		<FlatList data={cards()} style={{ flex: 1 }} getItemLayout={cardLayout}
			renderItem={(info: ListRenderItemInfo<Card>): NeonNode =>
				<View style={{ height: CARD - 6, marginBottom: 6, marginHorizontal: 12, padding: 12, backgroundColor: "#313244", borderRadius: 10 }}>
					<Text style={{ color: "#cdd6f4", fontSize: 16 }}>{info.item.title}</Text>
					<Text style={{ color: "#89b4fa", fontSize: 13 }}>{"value " + info.item.value.toString()}</Text>
				</View>} />
	</View>;
}
