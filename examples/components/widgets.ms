import { Accessor, createSignal } from "../../src/core/signal";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { Show } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable, ScrollView } from "../../src/components/primitives";
import { Chip } from "../../src/components/chip";
import { PageController, PageIndicator, PageRenderItemInfo, PageView } from "../../src/components/pageView";
import { Carousel, CarouselMode } from "../../src/components/carousel";
import { TabRoute, TabSceneInfo, TabView } from "../../src/components/tabView";
import { Accordion, ExpansionTile } from "../../src/components/collapsible";
import { DataColumn, DataRow, DataTable } from "../../src/components/dataTable";
import { Wrap, WrapAlignment } from "../../src/components/wrap";

const styles = createStyles({
	screen: { flex: 1, backgroundColor: "#11111b" },
	top: { paddingTop: 48, paddingLeft: 12, paddingRight: 12, paddingBottom: 8, gap: 6, backgroundColor: "#1e1e2e" },
	title: { color: "#cdd6f4", fontSize: 20, fontWeight: "bold" },
	status: { color: "#89b4fa", fontSize: 15 },
	tabs: { flexDirection: "row", flexWrap: "wrap", gap: 6 },
	tab: { paddingTop: 8, paddingBottom: 8, paddingLeft: 10, paddingRight: 10, backgroundColor: "#45475a", color: "#cdd6f4", borderRadius: 6 },
	body: { flex: 1 },
	page: { flex: 1, alignItems: "center", justifyContent: "center", padding: 32 },
	pageTitle: { color: "#11111b", fontSize: 28, fontWeight: "bold" },
	pageText: { color: "#11111b", fontSize: 17, marginTop: 12 },
	pagerFooter: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", paddingLeft: 16, paddingRight: 16, paddingBottom: 12 },
	button: { paddingTop: 10, paddingBottom: 10, paddingLeft: 16, paddingRight: 16, backgroundColor: "#89b4fa", borderRadius: 8, color: "#11111b" },
	scene: { flex: 1, backgroundColor: "#f5f5f5" },
	sceneRow: { height: 56, paddingLeft: 16, justifyContent: "center", backgroundColor: "#ffffff", marginBottom: 1 },
	sceneText: { color: "#1c1b1f", fontSize: 16 },
	slide: { flex: 1, margin: 8, borderRadius: 16, alignItems: "center", justifyContent: "center" },
	slideText: { color: "#11111b", fontSize: 24, fontWeight: "bold" },
	light: { flex: 1, backgroundColor: "#ffffff" },
	faqHeader: { height: 52, paddingLeft: 16, paddingRight: 16, flexDirection: "row", alignItems: "center", justifyContent: "space-between", backgroundColor: "#ffffff" },
	faqQuestion: { color: "#1c1b1f", fontSize: 16, fontWeight: "bold" },
	faqAnswer: { color: "#49454f", fontSize: 15, padding: 16, backgroundColor: "#f3edf7" },
	divider: { height: 1, backgroundColor: "#e0e0e0" },
});

const SLIDE_COLORS: string[] = ["#f38ba8", "#fab387", "#a6e3a1", "#89dceb", "#b4befe"];

interface Intro {
	title: string;
	text: string;
	color: string;
}

function intros(): Intro[] {
	return [
		{ title: "Welcome", text: "Swipe to see what Neon can do.", color: "#f9e2af" },
		{ title: "Sync", text: "Your notes follow you everywhere.", color: "#a6e3a1" },
		{ title: "Ready", text: "Start writing.", color: "#89dceb" },
	];
}

interface Faq {
	question: string;
	answer: string;
}

function faqs(): Faq[] {
	return [
		{ question: "What is Neon?", answer: "A reactive UI framework written in MetaScript." },
		{ question: "Which platforms?", answer: "iOS, Android, the browser and the terminal." },
		{ question: "Is it open source?", answer: "Yes, Neon and Ion are open source." },
		{ question: "Does it use Yoga?", answer: "Yes, layout is flexbox through Yoga." },
	];
}

interface Dessert {
	name: string;
	calories: int32;
	fat: int32;
}

function desserts(): Dessert[] {
	return [
		{ name: "Frozen yogurt", calories: 159, fat: 6 },
		{ name: "Ice cream", calories: 237, fat: 9 },
		{ name: "Eclair", calories: 262, fat: 16 },
		{ name: "Cupcake", calories: 305, fat: 4 },
		{ name: "Gingerbread", calories: 356, fat: 16 },
	];
}

function dessertBefore(a: Dessert, b: Dessert, column: number, up: boolean): boolean {
	let order = 0;
	if (column === 0) { order = a.name < b.name ? -1 : (a.name > b.name ? 1 : 0); }
	if (column === 1) { order = a.calories - b.calories; }
	if (column === 2) { order = a.fat - b.fat; }
	return up ? order < 0 : order > 0;
}

function sortedDesserts(list: Dessert[], column: number, up: boolean): Dessert[] {
	const out: Dessert[] = [];
	for (const d of list) {
		let at = out.length;
		while (at > 0 && dessertBefore(d, out[at - 1], column, up)) { at -= 1; }
		out.splice(at, 0, d);
	}
	return out;
}

function without(list: string[], name: string): string[] {
	const out: string[] = [];
	for (const n of list) {
		if (n !== name) { out.push(n); }
	}
	return out;
}

interface ScreenProps {
	say: (s: string) => void;
}

function OnboardingScreen(props: ScreenProps): NeonNode {
	const say = props.say;
	const controller = new PageController(0);
	const pages = intros();
	return <View style={styles.body}>
		<PageView data={pages} controller={controller} style={{ flex: 1 }}
			onPageSelected={(i: number): void => { say("page " + (i + 1).toString()); }}
			renderItem={(info: PageRenderItemInfo<Intro>): NeonNode => <View style={{ flex: 1, alignItems: "center", justifyContent: "center", padding: 32, backgroundColor: info.item.color }}>
				<Text style={styles.pageTitle}>{info.item.title}</Text>
				<Text style={styles.pageText}>{info.item.text}</Text>
			</View>} />
		<View style={styles.pagerFooter}>
			<Pressable style={styles.button} onPress={(): void => { controller.previousPage(); }}>back</Pressable>
			<PageIndicator count={pages.length} page={controller.page()} activeColor="#89b4fa"
				onPress={(i: number): void => { controller.setPage(i); }} />
			<Pressable style={styles.button} onPress={(): void => { controller.nextPage(); }}>next</Pressable>
		</View>
	</View>;
}

function chatRoutes(): TabRoute[] {
	return [{ key: "chats", title: "Chats" }, { key: "status", title: "Status" }, { key: "calls", title: "Calls" }];
}

function lines(prefix: string, count: int32): string[] {
	const out: string[] = [];
	for (let i = 1; i <= count; i += 1) { out.push(prefix + " " + i.toString()); }
	return out;
}

function TabsScreen(props: ScreenProps): NeonNode {
	const say = props.say;
	const [index, setIndex] = createSignal<number>(0);
	const routes = chatRoutes();
	return <TabView routes={routes} index={index()} lazy={true}
		onIndexChange={(i: number): void => { setIndex(i); say("tab " + routes[i as int32].title); }}
		renderLazyPlaceholder={(r: TabRoute): NeonNode => <View style={styles.scene}><Text style={styles.sceneText}>{"loading " + r.title}</Text></View>}
		renderScene={(info: TabSceneInfo): NeonNode => <ScrollView style={styles.scene}>
			{lines(info.route.title, 12).map((line: string): NeonNode => <View style={styles.sceneRow}><Text style={styles.sceneText}>{line}</Text></View>)}
		</ScrollView>} />;
}

function CarouselScreen(props: ScreenProps): NeonNode {
	const say = props.say;
	const [playing, setPlaying] = createSignal(true);
	const mode: CarouselMode = "parallax";
	const slides: string[] = ["Slide A", "Slide B", "Slide C", "Slide D", "Slide E"];
	return <View style={styles.body}>
		<Carousel data={slides} autoPlay={playing()} autoPlayInterval={2500} viewportFraction={0.8} mode={mode}
			style={{ height: 240, marginTop: 24 }}
			onSnapToItem={(i: number): void => { say("slide " + slides[i as int32]); }}
			renderItem={(info: PageRenderItemInfo<string>): NeonNode => <View style={{ flex: 1, margin: 8, borderRadius: 16, alignItems: "center", justifyContent: "center", backgroundColor: SLIDE_COLORS[(info.index() as int32) % SLIDE_COLORS.length] }}>
				<Text style={styles.slideText}>{info.item}</Text>
			</View>} />
		<View style={{ flexDirection: "row", justifyContent: "center", marginTop: 16 }}>
			<Pressable style={styles.button} onPress={(): void => { setPlaying(!playing()); say(playing() ? "autoplay on" : "autoplay off"); }}>{playing() ? "pause" : "play"}</Pressable>
		</View>
	</View>;
}

function FaqScreen(props: ScreenProps): NeonNode {
	const say = props.say;
	const [active, setActive] = createSignal<number[]>([]);
	const entries = faqs();
	return <ScrollView style={styles.light}>
		<ExpansionTile title="Shipping" subtitle="Three options"
			onExpansionChanged={(open: boolean): void => { say(open ? "shipping open" : "shipping closed"); }}>
			<Text style={styles.faqAnswer}>Standard, express or pick-up.</Text>
		</ExpansionTile>
		<View style={styles.divider} />
		<Accordion sections={entries} activeSections={active()}
			onChange={(next: number[]): void => { setActive(next); say("faq open " + next.join("|")); }}
			renderHeader={(s: Faq, i: number, open: Accessor<boolean>): NeonNode => <View style={styles.faqHeader}>
				<Text style={styles.faqQuestion}>{s.question}</Text>
				<Text style={styles.faqQuestion}>{open() ? "−" : "+"}</Text>
			</View>}
			renderContent={(s: Faq, i: number, open: Accessor<boolean>): NeonNode => <Text style={styles.faqAnswer}>{s.answer}</Text>} />
	</ScrollView>;
}

function TableScreen(props: ScreenProps): NeonNode {
	const say = props.say;
	const [items, setItems] = createSignal<Dessert[]>(desserts());
	const [sortColumn, setSortColumn] = createSignal<number>(-1);
	const [ascending, setAscending] = createSignal(true);
	const [chosen, setChosen] = createSignal<string[]>([]);
	const names: string[] = ["name", "calories", "fat"];
	const sortBy = (column: number, up: boolean): void => {
		setSortColumn(column);
		setAscending(up);
		setItems(sortedDesserts(items(), column, up));
		say("sorted " + names[column as int32] + (up ? " up" : " down"));
	};
	const columns: DataColumn[] = [
		{ label: "Dessert", onSort: sortBy },
		{ label: "Calories", numeric: true, onSort: sortBy },
		{ label: "Fat (g)", numeric: true, onSort: sortBy, tooltip: "Total fat in grams" },
	];
	const rows = (): DataRow[] => items().map((d: Dessert): DataRow => ({
		cells: [{ text: d.name }, { text: d.calories.toString() }, { text: d.fat.toString() }],
		selected: chosen().indexOf(d.name) >= 0,
		onSelectChanged: (on: boolean): void => {
			const next = without(chosen(), d.name);
			if (on) { next.push(d.name); }
			setChosen(next);
			say("selected " + (next.length === 0 ? "none" : next.join("|")));
		},
	}));
	return <View style={styles.light}>
		<DataTable columns={columns} rows={rows()} sortColumnIndex={sortColumn()} sortAscending={ascending()} />
	</View>;
}

function ChipsScreen(props: ScreenProps): NeonNode {
	const say = props.say;
	const [picked, setPicked] = createSignal<string[]>(["Neon"]);
	const tags: string[] = ["Neon", "Ion", "Yoga", "Void", "MetaScript", "iOS", "Android", "Browser", "Terminal", "Flexbox"];
	const centred: WrapAlignment = "center";
	return <View style={styles.light}>
		<Wrap spacing={8} runSpacing={12} alignment={centred} style={{ padding: 16 }}>
			{tags.map((tag: string): NeonNode => <Chip label={tag} selected={picked().indexOf(tag) >= 0} showSelectedCheck={true}
				onPress={(e: NeonEvent): void => {
					const had = picked().indexOf(tag) >= 0;
					const next = without(picked(), tag);
					if (!had) { next.push(tag); }
					setPicked(next);
					say("chips " + next.join("|"));
				}} />)}
		</Wrap>
	</View>;
}

export function Widgets(): NeonNode {
	const [screen, setScreen] = createSignal<int32>(0);
	const [status, setStatus] = createSignal("ready");
	const say = (s: string): void => { setStatus(s); };
	return <View style={styles.screen}>
		<View style={styles.top}>
			<Text style={styles.title}>Neon widgets</Text>
			<Text style={styles.status}>{"status " + status()}</Text>
			<View style={styles.tabs}>
				<Pressable style={styles.tab} onPress={() => { setScreen(0); say("onboarding"); }}>onboarding</Pressable>
				<Pressable style={styles.tab} onPress={() => { setScreen(1); say("tabs"); }}>tabs</Pressable>
				<Pressable style={styles.tab} onPress={() => { setScreen(2); say("carousel"); }}>carousel</Pressable>
				<Pressable style={styles.tab} onPress={() => { setScreen(3); say("faq"); }}>faq</Pressable>
				<Pressable style={styles.tab} onPress={() => { setScreen(4); say("table"); }}>table</Pressable>
				<Pressable style={styles.tab} onPress={() => { setScreen(5); say("chips"); }}>chips</Pressable>
			</View>
		</View>
		<Show when={screen() === 0}><OnboardingScreen say={say} /></Show>
		<Show when={screen() === 1}><TabsScreen say={say} /></Show>
		<Show when={screen() === 2}><CarouselScreen say={say} /></Show>
		<Show when={screen() === 3}><FaqScreen say={say} /></Show>
		<Show when={screen() === 4}><TableScreen say={say} /></Show>
		<Show when={screen() === 5}><ChipsScreen say={say} /></Show>
	</View>;
}
