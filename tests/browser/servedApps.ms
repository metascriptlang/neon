import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable, ScrollView, TextInput } from "../../src/components/primitives";
import { Switch } from "../../src/components/switch";
import { ActivityIndicator } from "../../src/components/activityIndicator";
import { Head } from "../../src/render/head";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal, Accessor } from "../../src/core/signal";

export const styles = createStyles({ box: { padding: 8 }, label: { color: "#334" } });

when (js) {
	export extern function servedPart(name: cstring, part: cstring): string from
		"((n, p) => { const s = globalThis.neonServed?.[n]; if (s === undefined) { throw new Error('no server page named ' + n + ': tests/browser/run.sh renders them from tests/browser/serveApps.ms'); } return s[p]; })(#, #)";
}

export function docs(
	name: Accessor<string>,
	blank: Accessor<string>,
	open: Accessor<boolean>,
	rows: Accessor<string[]>,
	press: (e: NeonEvent) => void,
	mech: (n: HostNode) => void,
): NeonNode {
	return <View accessibilityLabel="Docs" style={styles.box}>
		<Text style={styles.label}>Hi {name()}</Text>
		<Text>{blank()}</Text>
		<Pressable accessibilityLabel="Copy" onPress={press}><Text>copy</Text></Pressable>
		<Show when={open()}><p id="shown">shown</p></Show>
		<For each={rows()}>{(row: string, i: Accessor<number>): NeonNode => <span class="row">{row}</span>}</For>
		<canvas id="mech" ref={mech}></canvas>
		<a href="/docs" title={name()}>docs &amp; more</a>
	</View>;
}

export function docsAtStart(): NeonNode {
	const [name, _name] = createSignal("Ann");
	const [blank, _blank] = createSignal("");
	const [open, _open] = createSignal(true);
	const [rows, _rows] = createSignal<string[]>(["a", "b", "c"]);
	return docs(name, blank, open, rows, (e: NeonEvent): void => {}, (node: HostNode): void => {});
}

export function scrollApp(onScroll: (e: NeonEvent) => void): NeonNode {
	return <View>
		<ScrollView horizontal={true} showsHorizontalScrollIndicator={false} onScroll={onScroll}>
			<Text>row</Text>
		</ScrollView>
	</View>;
}

export function clampedApp(): NeonNode {
	return <View><Text numberOfLines={3}>long</Text></View>;
}

export function switchApp(on: Accessor<boolean>, onValueChange: (v: boolean) => void): NeonNode {
	return <View>
		<Switch value={on()} onValueChange={onValueChange} />
		<ActivityIndicator animating={on()} color="#c00" />
	</View>;
}

export function switchAppOn(): NeonNode {
	const [on, _on] = createSignal(true);
	return switchApp(on, (v: boolean): void => {});
}

export function textareaApp(onChangeText: (t: string) => void): NeonNode {
	return <View>
		<TextInput multiline={true} defaultValue="note" onChangeText={onChangeText} />
	</View>;
}

export function plainTextareaApp(): NeonNode {
	return <View><TextInput multiline={true} defaultValue="note" /></View>;
}

export function HeadPage(props: { title: Accessor<string> }): NeonNode {
	return <View>
		<Head>
			<title>{props.title()}</title>
			<meta name="description" content="about this page" />
		</Head>
		<Text>body</Text>
	</View>;
}

export function headPageAtStart(): NeonNode {
	const [title, _title] = createSignal("Docs");
	return <HeadPage title={title} />;
}

export function primitivesApp(): NeonNode {
	return <View accessibilityLabel="Page" style={styles.box}>
		<Text style={styles.label}>café &amp; · …</Text>
		<Pressable accessibilityLabel="Open"><Text>go</Text></Pressable>
		<TextInput editable={false} secureTextEntry={true} keyboardType="number-pad" maxLength={4}
			autoCorrect={false} accessibilityRole="search" placeholder="PIN" />
		<TextInput editable={true} autoFocus={false} accessibilityLabel="Name" />
	</View>;
}

export function marksApp(): NeonNode {
	const [on, _on] = createSignal(false);
	const [open, _open] = createSignal(true);
	const [blank, _blank] = createSignal("");
	const [count, _count] = createSignal(3);
	const [rows, _rows] = createSignal<string[]>(["a", "b"]);
	return <View>
		<Text>count: {count().toString()} items</Text>
		<Text>{blank()}</Text>
		<Show when={on()}><Text>hidden</Text></Show>
		<Show when={open()}><Text>shown</Text></Show>
		<For each={rows()}>{(row: string, i: Accessor<number>): NeonNode => <Text>{row}</Text>}</For>
		<Text>tail</Text>
	</View>;
}

export function scrollViewApp(): NeonNode {
	return <View>
		<ScrollView horizontal={false}><Text>row</Text></ScrollView>
	</View>;
}

export function linesApp(): NeonNode {
	return <View>
		<Text numberOfLines={2}>long</Text>
		<Text numberOfLines={0}>free</Text>
	</View>;
}

export function switchesApp(): NeonNode {
	return <View>
		<Switch value={true} accessibilityLabel="Wi-Fi" />
		<Switch value={false} disabled={true} thumbColor="#fff" trackColorOn="#0a0" trackColorOff="#ccc" />
		<ActivityIndicator />
		<ActivityIndicator animating={false} hidesWhenStopped={false} color="#c00" size="large" />
	</View>;
}

export function textareasApp(): NeonNode {
	return <View>
		<TextInput multiline={true} defaultValue="note" placeholder="Write" />
		<TextInput multiline={true} value={"\nfirst <b> & \"second\""} editable={false} maxLength={40} />
		<TextInput multiline={true} />
	</View>;
}
