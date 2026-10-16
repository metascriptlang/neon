import { sleepAsync } from "std/core/promise";
import { NeonNode } from "../../src/render/hostTypes";
import { renderToMarkup, renderToStream } from "../../src/render/ssr";
import { createAsyncMemo } from "../../src/core/memo";
import { Host, HostNode } from "../../src/render/hostTypes";
import { View, Text, Pressable, ScrollView, TextInput } from "../../src/components/primitives";
import { Switch } from "../../src/components/switch";
import { Head } from "../../src/render/head";
import { Portal } from "../../src/render/portal";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { Accessor, createSignal } from "../../src/core/signal";
import { createList } from "../../src/core/list";
import { createUniqueId } from "../../src/core/owner";
import { page } from "../edge/pages";
import { respond } from "../../examples/site/server";

const styles = createStyles({ row: { padding: 8, flexDirection: "row" }, label: { color: "#334", fontSize: 14 } });

function rowsPage(rows: number[]): NeonNode {
	return <View accessibilityLabel="List" style={styles.row}>
		<For each={rows}>{(n: number, i: Accessor<number>): NeonNode =>
			<View style={styles.row}>
				<Text style={styles.label}>Row {n.toString()}</Text>
				<a href={"/item/" + n.toString()} title={"Item & " + n.toString()}>open "{n.toString()}"</a>
				<Pressable accessibilityLabel="Copy"><Text>copy</Text></Pressable>
			</View>}</For>
	</View>;
}

function Ided(): NeonNode {
	const id = createUniqueId();
	return <Text>{id}</Text>;
}

const boom: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
	throw new Error("boom");
};

function fixtures(): NeonNode {
	const list = createList<number>([3, 4]);
	const [on, setOn] = createSignal(true);
	const none: number[] = [];
	return <View>
		<Head><title>Fixtures</title><meta name="description" content="a & b" /></Head>
		<Head><title>Fixtures again</title><meta name="description" content="second" /></Head>
		<Ided />
		<Show when={on}><Text>shown</Text></Show>
		<Ided />
		<Show when={false} fallback={<Text>fallback</Text>}><Text>hidden</Text></Show>
		<Ided />
		<For each={none} fallback={<Text>none</Text>}>{(n: number, i: Accessor<number>): NeonNode => <Text>{n.toString()}</Text>}</For>
		<For each={[1, 2]} keyed={false}>{(v: Accessor<number>, i: number): NeonNode => <Text>{v().toString()}</Text>}</For>
		<ForList each={list}>{(v: Accessor<number>): NeonNode => <Text>{v().toString()}</Text>}</ForList>
		<View><Show when={on}><Text>first</Text></Show><Text>after</Text></View>
		<For each={[1, 2]}>{(n: number, i: Accessor<number>): NeonNode => <Show when={on}><Text>{n.toString()}</Text><Ided /></Show>}</For>
		<Errored fallback={(err: Accessor<Error>, reset: () => void): NeonNode => <Text>caught {err().message}</Text>}>
			<Text>partial</Text>
			{boom}
		</Errored>
		<Ided />
		<Portal><Text>over</Text></Portal>
		<Text>{"a"}{"b"}{""}{"<&>"}</Text>
		<Switch value={true} />
		<ScrollView horizontal={true} showsHorizontalScrollIndicator={false}><Text>scroll</Text></ScrollView>
		<TextInput multiline={true} value={"\nline"} />
		<Text numberOfLines={2}>clamped</Text>
		<style>{".x > .y { color: red }"}</style>
		<script>{"if (a < b && c) {}"}</script>
		<Ided />
	</View>;
}

async function afterStr(ms: int32, value: string): Promise<string> {
	await sleepAsync(ms);
	return value;
}

async function afterInt(ms: int32, value: int32): Promise<int32> {
	await sleepAsync(ms);
	return value;
}

function Visits(): NeonNode {
	const visits = createAsyncMemo((p: int32 | null): Promise<int32> => afterInt(2, 1234));
	return <Text>{visits} visits</Text>;
}

function Profile(): NeonNode {
	const name = createAsyncMemo((p: string | null): Promise<string> => afterStr(4, "Ada </b> & \"Lovelace\""));
	return <View>
		<Text>{name}</Text>
		<Loading fallback={<Text>counting</Text>}><Visits /></Loading>
	</View>;
}

function asyncPage(): NeonNode {
	return <View accessibilityLabel="Profile">
		<Head><title>Profile</title></Head>
		<Loading fallback={<Text>loading</Text>}><Profile /></Loading>
		<Text>footer</Text>
	</View>;
}

function dump(name: string, node: NeonNode): void {
	const markup = renderToMarkup(node);
	console.log("== " + name + " html\n" + markup.html);
	console.log("== " + name + " head\n" + markup.head);
	console.log("== " + name + " css\n" + markup.css);
}

async function dumpAwaited(name: string, node: NeonNode): Promise<void> {
	const markup = await renderToStream(node);
	console.log("== " + name + " html\n" + markup.html);
	console.log("== " + name + " head\n" + markup.head);
	console.log("== " + name + " css\n" + markup.css);
	console.log("== " + name + " records\n" + markup.records);
}

async function main(): Promise<void> {
	const rows: number[] = [];
	for (let i = 0; i < 20; i += 1) { rows.push(i); }
	dump("rows", rowsPage(rows));
	dump("fixtures", fixtures());
	for (const path of ["/", "/guide"]) {
		console.log("== edge " + path + "\n" + page(path));
	}
	for (const url of ["/", "/docs/start", "/docs/routing?x=1#top", "/docs/missing", "/nowhere", "/docs/start/"]) {
		const r = respond(url);
		console.log("== site " + url + " " + r.status.toString() + " " + (r.location ?? "") + "\n" + r.body);
	}
	await dumpAwaited("async", asyncPage());
}
await main();
