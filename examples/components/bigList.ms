import { Accessor, createSignal } from "../../src/core/signal";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable } from "../../src/components/primitives";
import { FlatList, FlatListHandle, ItemLayout, ListRenderItemInfo, ScrollToIndexFailedInfo } from "../../src/components/flatList";
import { SectionBase, SectionInfo, SectionList, SectionListHandle, SectionListRenderItemInfo } from "../../src/components/sectionList";
import { Show } from "../../src/macros/ui/flow";
import { Style } from "../../src/render/style";

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

function measuredRowStyle(n: number): Style {
	return {
		height: n % 8 === 0 ? 96 : 48 + (n % 3) * 32,
		padding: 12, color: "#cdd6f4",
		backgroundColor: n % 8 === 0 ? "#1e66a1" : "#313244",
	};
}

function MeasuredStickyList(props: { inverted: Accessor<boolean> }): NeonNode {
	const data: Entry[] = [];
	for (let i = 0; i < 64; i += 1) { data.push({ id: "m" + i.toString(), n: i }); }
	const [offset, setOffset] = createSignal<number>(0);
	const [pressed, setPressed] = createSignal("none");
	const [ends, setEnds] = createSignal<int32>(0);
	const handles: FlatListHandle[] = [];
	return <View style={styles.screen}>
		<Text style={styles.title}>Measured sticky list</Text>
		<Text style={styles.status}>{"offset " + Math.round(offset()).toString()}</Text>
		<Text style={styles.status}>{"pressed " + pressed()}</Text>
		<Text style={styles.status}>{"ends " + ends().toString()}</Text>
		<Pressable style={styles.jump} onPress={() => handles[0].scrollToEnd({ animated: false })}>measured end</Pressable>
		<FlatList data={data} style={styles.list} inverted={props.inverted}
			stickyHeaderIndices={[0, 8, 16, 24, 32, 40, 48, 56]}
			initialNumToRender={2} maxToRenderPerBatch={4} windowSize={3}
			ref={(h: FlatListHandle): void => { handles.push(h); }}
			onScroll={(e: NeonEvent): void => { setOffset(e.y); }}
			onEndReached={() => setEnds(ends() + 1)}
			ListFooterComponent={<View style={{ height: 48, backgroundColor: "#45475a" }}><Text style={styles.status}>List end</Text></View>}
			renderItem={(info: ListRenderItemInfo<Entry>): NeonNode =>
				<Pressable style={measuredRowStyle(info.item.n)}
					onPress={() => setPressed((info.item.n % 8 === 0 ? "header " : "item ") + info.item.n.toString())}>
					{(info.item.n % 8 === 0 ? "header " : "item ") + info.item.n.toString()}
				</Pressable>} />
	</View>;
}

function GridList(): NeonNode {
	const start: Entry[] = [];
	for (let i = 0; i < 60; i += 1) { start.push({ id: "g" + i.toString(), n: i }); }
	const [data, setData] = createSignal<Entry[]>(start);
	const [next, setNext] = createSignal<number>(60);
	const [pressed, setPressed] = createSignal("none");
	const fresh = (): Entry => {
		const n = next();
		setNext(n + 1);
		return { id: "g" + n.toString(), n };
	};
	return <View style={styles.screen}>
		<Text style={styles.title}>Grid</Text>
		<Text style={styles.status}>{"pressed " + pressed()}</Text>
		<View style={{ flexDirection: "row", gap: 8 }}>
			<Pressable style={styles.jump} onPress={() => setData([fresh(), ...data()])}>prepend</Pressable>
			<Pressable style={styles.jump} onPress={() => setData([...data(), fresh()])}>append</Pressable>
		</View>
		<FlatList data={data()} style={styles.list} numColumns={3} columnWrapperStyle={{ gap: 4, marginBottom: 4 }}
			renderItem={(info: ListRenderItemInfo<Entry>): NeonNode =>
				<Pressable style={{ flex: 1, height: 64, padding: 12, backgroundColor: "#313244", color: "#cdd6f4" }}
					onPress={() => setPressed("cell " + info.item.n.toString() + " at " + info.index().toString())}>
					{"cell " + info.item.n.toString()}
				</Pressable>} />
	</View>;
}

function SectionsList(): NeonNode {
	const groups: SectionBase<Entry>[] = [];
	for (let s = 0; s < 20; s += 1) {
		const data: Entry[] = [];
		for (let i = 0; i < 2 + s % 5; i += 1) { data.push({ id: "s" + s.toString() + "-" + i.toString(), n: s * 100 + i }); }
		groups.push({ key: "Section " + s.toString(), data });
	}
	const [pressed, setPressed] = createSignal("none");
	const handles: SectionListHandle[] = [];
	return <View style={styles.screen}>
		<Text style={styles.title}>Sections</Text>
		<Text style={styles.status}>{"pressed " + pressed()}</Text>
		<Pressable style={styles.jump} onPress={() => handles[0].scrollToLocation({ sectionIndex: 1, itemIndex: 0, animated: false })}>section 1</Pressable>
		<SectionList sections={groups} style={styles.list} stickySectionHeadersEnabled={true}
			ref={(h: SectionListHandle): void => { handles.push(h); }}
			onScrollToIndexFailed={(info: ScrollToIndexFailedInfo): void => { setPressed("jump waits for row " + info.index.toString() + " to be measured"); }}
			ItemSeparatorComponent={<View style={{ height: 1, backgroundColor: "#45475a" }} />}
			renderSectionHeader={(info: SectionInfo<SectionBase<Entry>>): NeonNode =>
				<View style={{ height: 36, padding: 8, backgroundColor: "#1e66a1" }}><Text style={styles.status}>{info.section.key as string}</Text></View>}
			renderItem={(info: SectionListRenderItemInfo<Entry, SectionBase<Entry>>): NeonNode =>
				<Pressable style={{ height: 56, padding: 12, backgroundColor: "#313244", color: "#cdd6f4" }}
					onPress={() => setPressed((info.section().key as string) + " item " + info.index().toString())}>
					{"item " + info.item.n.toString()}
				</Pressable>} />
	</View>;
}

export function ListAcceptance(): NeonNode {
	const [mode, setMode] = createSignal<int32>(0);
	return <View style={{ flex: 1 }}>
		<View style={{ flexDirection: "row", flexWrap: "wrap", gap: 8, padding: 8 }}>
			<Pressable style={styles.jump} onPress={() => setMode(0)}>fixed rows</Pressable>
			<Pressable style={styles.jump} onPress={() => setMode(1)}>measured rows</Pressable>
			<Pressable style={styles.jump} onPress={() => setMode(2)}>inverted rows</Pressable>
			<Pressable style={styles.jump} onPress={() => setMode(3)}>grid</Pressable>
			<Pressable style={styles.jump} onPress={() => setMode(4)}>sections</Pressable>
		</View>
		<Show when={mode() === 4} fallback={<Show when={mode() === 3} fallback={<Show when={mode() === 0} fallback={<MeasuredStickyList inverted={mode() === 2} />}>
			<BigList />
		</Show>}>
			<GridList />
		</Show>}>
			<SectionsList />
		</Show>
	</View>;
}
