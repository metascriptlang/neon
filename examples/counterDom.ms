import { createSignal } from "../src/core/signal";
import { element } from "../src/macros/ui/element";
import { render } from "../src/render/host";
import { domHost, documentBody } from "../src/platform/browser/dom";
import { View, Text, Pressable } from "../src/components/primitives";
import { generatedMain } from "./genSource";

function main(): void {
	const [count, setCount] = createSignal(0);

	const generated = generatedMain();
	const app = element(
		<View style={{ height: 20, display: "flex", flexDirection: "column", alignItems: "flex-start", gap: 12, padding: 16, backgroundColor: "#1e1e2e", color: "#cdd6f4", borderRadius: 8 }}>
			<Text>Counter!: {count() + ""}</Text>
			<Pressable onPress={() => setCount(count() + 1)}>+</Pressable>
			<Text>JSX above compiled to:{count}</Text>
			<pre style={{ padding: 12, backgroundColor: "#11111b", color: "#a6e3a1", borderRadius: 6, fontSize: 12 }}>{generated}</pre>
		</View>
	);
	render(app, domHost(), documentBody());
}

main();
