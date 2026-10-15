import { renderToMarkup } from "../../src/render/ssr";
import { NeonNode } from "../../src/render/hostTypes";
import { View, Text, Pressable } from "../../src/components/primitives";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { Accessor } from "../../src/core/signal";

const styles = createStyles({ row: { padding: 8, flexDirection: "row" }, label: { color: "#334", fontSize: 14 } });

function page(rows: number[]): NeonNode {
	return <View accessibilityLabel="List" style={styles.row}>
		<For each={rows}>{(n: number, i: Accessor<number>): NeonNode =>
			<View style={styles.row}>
				<Text style={styles.label}>Row {n.toString()}</Text>
				<a href={"/item/" + n.toString()} title={"Item & " + n.toString()}>open "{n.toString()}"</a>
				<Pressable accessibilityLabel="Copy"><Text>copy</Text></Pressable>
			</View>}</For>
	</View>;
}

function main(): void {
	const rows: number[] = [];
	for (let i = 0; i < 500; i += 1) { rows.push(i); }
	let html = "";
	let spent: float64 = 0.0;
	const warm = 30;
	const rounds = 300;
	for (let r = 0; r < warm + rounds; r += 1) {
		const a = performance.now();
		html = renderToMarkup(page(rows)).html;
		const b = performance.now();
		if (r >= warm) { spent += b - a; }
	}
	console.log("render ms=" + (spent / rounds).toString() + " bytes=" + html.length.toString());
}
main();
