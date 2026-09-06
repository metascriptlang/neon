import { createSignal } from "../src/core/signal";
import { element } from "../src/macros/ui/element";
import { renderToHost } from "../src/render/host";
import { domHost, documentBody } from "../src/platform/browser/dom";
import { View, Text, Pressable } from "../src/components/primitives";

function main(): void {
	const [count, setCount] = createSignal(0);
	const app = element(
		<View style={{ padding: 16, backgroundColor: "#1e1e2e", color: "#cdd6f4", borderRadius: 8 }}>
			<Text>Counter: {count() + ""}</Text>
			<Pressable onPress={() => setCount(count() + 1)}>+</Pressable>
		</View>
	);
	renderToHost(app, domHost(), documentBody());
}

main();
