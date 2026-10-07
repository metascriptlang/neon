import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { Show } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable } from "../../src/components/primitives";
import { FlatList, ListRenderItemInfo } from "../../src/components/flatList";
import { Dismissible, DismissDirection } from "../../src/components/dismissible";
import { ReorderableFlatList, ReorderableRenderItemInfo } from "../../src/components/reorderableList";
import { GridList, GridRenderItemInfo, MasonryList, MasonryRenderItemInfo } from "../../src/components/gridList";
import {
	CollapsingHeader,
	CustomScrollView,
	createScrollOffset,
	sliverGrid,
	sliverList,
	sliverPinnedHeader,
	sliverToBox,
} from "../../src/components/sliver";

const styles = createStyles({
	screen: { display: "flex", flex: 1, minHeight: 0, flexDirection: "column", backgroundColor: "#11111b" },
	top: { paddingTop: 48, paddingLeft: 12, paddingRight: 12, paddingBottom: 8, gap: 6, backgroundColor: "#1e1e2e" },
	title: { color: "#cdd6f4", fontSize: 20, fontWeight: "bold" },
	status: { color: "#89b4fa", fontSize: 15 },
	tabs: { flexDirection: "row", flexWrap: "wrap", gap: 6 },
	tab: { paddingTop: 8, paddingBottom: 8, paddingLeft: 10, paddingRight: 10, backgroundColor: "#45475a", color: "#cdd6f4", borderRadius: 6 },
	body: { display: "flex", flexDirection: "column", flex: 1, minHeight: 0 },
	mail: { height: 64, paddingLeft: 16, paddingRight: 16, justifyContent: "center", backgroundColor: "#313244" },
	mailText: { color: "#cdd6f4", fontSize: 17 },
	archive: { flex: 1, justifyContent: "center", paddingLeft: 20, backgroundColor: "#40a02b" },
	remove: { flex: 1, justifyContent: "center", alignItems: "flex-end", paddingRight: 20, backgroundColor: "#d20f39" },
	backgroundText: { color: "#ffffff", fontSize: 16, fontWeight: "bold" },
	separator: { height: 1, backgroundColor: "#11111b" },
	song: { height: 56, flexDirection: "row", alignItems: "center", paddingLeft: 16, backgroundColor: "#313244" },
	songText: { flex: 1, color: "#cdd6f4", fontSize: 17 },
	handle: { width: 64, height: 56, alignItems: "center", justifyContent: "center", backgroundColor: "#585b70" },
	handleText: { color: "#cdd6f4", fontSize: 15 },
	photo: { margin: 2, alignItems: "center", justifyContent: "center", borderRadius: 4 },
	photoText: { color: "#11111b", fontSize: 14, fontWeight: "bold" },
	row: { height: 52, paddingLeft: 16, justifyContent: "center", backgroundColor: "#1e1e2e" },
	rowText: { color: "#cdd6f4", fontSize: 16 },
	headerBox: { backgroundColor: "#7287fd" },
	headerTitle: { color: "#ffffff", fontSize: 20, fontWeight: "bold" },
	pinned: { height: 44, paddingLeft: 16, justifyContent: "center", backgroundColor: "#f5c2e7" },
	pinnedText: { color: "#11111b", fontSize: 16, fontWeight: "bold" },
	banner: { height: 120, alignItems: "center", justifyContent: "center", backgroundColor: "#94e2d5" },
});

interface Mail {
	subject: string;
}

interface Song {
	title: string;
}

interface Photo {
	label: string;
	color: string;
	height: number;
}

const PALETTE: string[] = ["#f38ba8", "#fab387", "#f9e2af", "#a6e3a1", "#94e2d5", "#89dceb", "#74c7ec", "#b4befe"];

function mails(): Mail[] {
	const out: Mail[] = [];
	for (let i = 1; i <= 30; i += 1) { out.push({ subject: "Mail " + i.toString() }); }
	return out;
}

function songs(): Song[] {
	const out: Song[] = [];
	for (let i = 1; i <= 12; i += 1) { out.push({ title: "Song " + i.toString() }); }
	return out;
}

function photos(): Photo[] {
	const out: Photo[] = [];
	for (let i = 1; i <= 40; i += 1) {
		out.push({ label: "P" + i.toString(), color: PALETTE[i % PALETTE.length], height: 80 + (i * 37) % 120 });
	}
	return out;
}

function moved<T>(list: T[], from: int32, to: int32): T[] {
	const rest: T[] = [];
	for (let i = 0; i < list.length; i += 1) {
		if (i !== from) { rest.push(list[i]); }
	}
	const out: T[] = [];
	for (let i = 0; i < rest.length; i += 1) {
		if (i === to) { out.push(list[from]); }
		out.push(rest[i]);
	}
	if (to >= rest.length) { out.push(list[from]); }
	return out;
}

function without(list: Mail[], gone: Mail): Mail[] {
	const out: Mail[] = [];
	for (const mail of list) {
		if (mail !== gone) { out.push(mail); }
	}
	return out;
}

interface ScreenProps {
	say: (s: string) => void;
}

interface PhotoProps {
	say: (s: string) => void;
	masonry: Accessor<boolean>;
}

function MailScreen(props: ScreenProps): NeonNode {
	const say = props.say;
	const [inbox, setInbox] = createSignal<Mail[]>(mails());
	return <FlatList data={inbox()} style={styles.body}
		ItemSeparatorComponent={<View style={styles.separator} />}
		renderItem={(info: ListRenderItemInfo<Mail>): NeonNode => <Dismissible
			background={<View style={styles.archive}><Text style={styles.backgroundText}>Archive</Text></View>}
			secondaryBackground={<View style={styles.remove}><Text style={styles.backgroundText}>Delete</Text></View>}
			onDismissed={(direction: DismissDirection): void => {
				say((direction === "startToEnd" ? "archived " : "deleted ") + info.item.subject);
				setInbox(without(inbox(), info.item));
			}}>
			<Pressable style={styles.mail} onPress={(): void => { say("opened " + info.item.subject); }}>
				<Text style={styles.mailText}>{info.item.subject}</Text>
			</Pressable>
		</Dismissible>} />;
}

function order(list: Song[]): string {
	const titles: string[] = [];
	for (let i = 0; i < 4 && i < list.length; i += 1) { titles.push(list[i].title.slice(5, list[i].title.length)); }
	return "order " + titles.join(" ");
}

function PlaylistScreen(props: ScreenProps): NeonNode {
	const say = props.say;
	const [playlist, setPlaylist] = createSignal<Song[]>(songs());
	say(order(playlist()));
	return <ReorderableFlatList data={playlist()} style={styles.body}
		activeItemStyle={{ opacity: 0.85, backgroundColor: "#6c7086" }}
		onReorder={(from: number, to: number): void => {
			const next = moved<Song>(playlist(), from as int32, to as int32);
			setPlaylist(next);
			say(order(next) + " moved " + from.toString() + " to " + to.toString());
		}}
		renderItem={(info: ReorderableRenderItemInfo<Song>): NeonNode => <View style={styles.song}>
			<Text style={styles.songText}>{info.item.title}</Text>
			<Pressable style={styles.handle} delayLongPress={250} onLongPress={(e: NeonEvent): void => { info.drag(); }}>
				<Text style={styles.handleText}>{"drag " + info.item.title.slice(5, info.item.title.length)}</Text>
			</Pressable>
		</View>} />;
}

function PhotoScreen(props: PhotoProps): NeonNode {
	const say = props.say;
	const gallery = photos();
	return <Show when={props.masonry()} fallback={<GridList data={gallery} maxItemWidth={110} childAspectRatio={1} itemSpacing={4} rowSpacing={4}
		renderItem={(info: GridRenderItemInfo<Photo>): NeonNode => {
			if (info.index() === 0) { say("grid width " + Math.round(info.itemWidth()).toString()); }
			return <View style={{ flex: 1, margin: 2, alignItems: "center", justifyContent: "center", borderRadius: 4, backgroundColor: info.item.color }}><Text style={styles.photoText}>{info.item.label}</Text></View>;
		}} />}>
		<MasonryList data={gallery} maxItemWidth={140} itemSpacing={4}
			getItemHeight={(item: Photo, index: number, width: number): number => item.height}
			renderItem={(info: MasonryRenderItemInfo<Photo>): NeonNode => <View style={{ height: info.item.height, alignItems: "center", justifyContent: "center", borderRadius: 4, backgroundColor: info.item.color }}>
				<Text style={styles.photoText}>{info.item.label + " c" + info.column.toString()}</Text>
			</View>} />
	</Show>;
}

interface Line {
	text: string;
}

function rows(count: number, prefix: string): Line[] {
	const out: Line[] = [];
	for (let i = 1; i <= count; i += 1) { out.push({ text: prefix + " " + i.toString() }); }
	return out;
}

function HeaderScreen(props: ScreenProps): NeonNode {
	const say = props.say;
	const scroll = createScrollOffset(false);
	const lines = rows(50, "Row");
	return <View style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0, position: "relative" }}>
		<FlatList data={lines} style={styles.body} contentContainerStyle={{ paddingTop: 200 }} onScroll={scroll.onScroll} scrollEventThrottle={16}
			renderItem={(info: ListRenderItemInfo<Line>): NeonNode => <View style={styles.row}><Text style={styles.rowText}>{info.item.text}</Text></View>} />
		<CollapsingHeader scrollOffset={scroll.offset} expandedHeight={200} collapsedHeight={64} pinned={true}
			style={styles.headerBox}
			onProgress={(progress: number): void => { say("header " + Math.round(200 - progress * 136).toString()); }}
			background={<View style={{ flex: 1, backgroundColor: "#b4befe" }} />}
			title={<Text style={styles.headerTitle}>Collapsing</Text>} />
	</View>;
}

function SliverScreen(): NeonNode {
	const albums = rows(9, "Album");
	const tracks = rows(30, "Track");
	return <CustomScrollView style={styles.body} slivers={[
		sliverToBox(<View style={styles.banner}><Text style={styles.pinnedText}>Library</Text></View>),
		sliverPinnedHeader(<View style={styles.pinned}><Text style={styles.pinnedText}>Albums</Text></View>),
		sliverGrid<Line>(accessor((): Line[] => albums), 3, (album: Line, i: Accessor<number>): NeonNode =>
			<View style={{ height: 90, margin: 2, alignItems: "center", justifyContent: "center", backgroundColor: PALETTE[(i() as int32) % PALETTE.length] }}>
				<Text style={styles.photoText}>{album.text}</Text>
			</View>, null),
		sliverPinnedHeader(<View style={styles.pinned}><Text style={styles.pinnedText}>Tracks</Text></View>),
		sliverList<Line>(accessor((): Line[] => tracks), (track: Line, i: Accessor<number>): NeonNode =>
			<View style={styles.row}><Text style={styles.rowText}>{track.text}</Text></View>),
	]} />;
}

export function FlutterLists(): NeonNode {
	const [screen, setScreen] = createSignal<int32>(0);
	const [status, setStatus] = createSignal("ready");
	const [masonry, setMasonry] = createSignal(false);
	const say = (s: string): void => { setStatus(s); };
	return <View style={styles.screen}>
		<View style={styles.top}>
			<Text style={styles.title}>Neon Flutter lists</Text>
			<Text style={styles.status}>{"status " + status()}</Text>
			<View style={styles.tabs}>
				<Pressable style={styles.tab} onPress={() => { setScreen(0); say("mail"); }}>mail</Pressable>
				<Pressable style={styles.tab} onPress={() => { setScreen(1); }}>playlist</Pressable>
				<Pressable style={styles.tab} onPress={() => { setScreen(2); say("photos"); }}>photos</Pressable>
				<Pressable style={styles.tab} onPress={() => { setMasonry(!masonry()); say(masonry() ? "masonry" : "grid"); }}>{masonry() ? "show grid" : "show masonry"}</Pressable>
				<Pressable style={styles.tab} onPress={() => { say("header"); setScreen(3); }}>header</Pressable>
				<Pressable style={styles.tab} onPress={() => { setScreen(4); say("slivers"); }}>slivers</Pressable>
			</View>
		</View>
		<Show when={screen() === 0}><MailScreen say={say} /></Show>
		<Show when={screen() === 1}><PlaylistScreen say={say} /></Show>
		<Show when={screen() === 2}><PhotoScreen say={say} masonry={masonry()} /></Show>
		<Show when={screen() === 3}><HeaderScreen say={say} /></Show>
		<Show when={screen() === 4}><SliverScreen /></Show>
	</View>;
}
