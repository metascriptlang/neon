import { createSignal } from "../src/core/signal";
import { element } from "../src/macros/ui/element";
import { renderToHost } from "../src/render/host";
import { domHost, documentBody } from "../src/platform/browser/dom";
import { View, Text, Pressable } from "../src/components/primitives";

const [count, setCount] = createSignal(0);

const view = <View class="card">
	<Text class="kicker">NEON REACTIVE</Text>
	<Text class="badge">{count() + ""}</Text>
	<Text class="meta">square {count() * count() + ""} - {count() % 2 === 0 ? "even" : "odd"}</Text>
	<View class="row">
		<Pressable class="btn ghost" onPress={() => setCount(count() - 1)}>-</Pressable>
		<Pressable class="btn" onPress={() => setCount(0)}>reset</Pressable>
		<Pressable class="btn solid" onPress={() => setCount(count() + 1)}>+</Pressable>
	</View>
</View>;

renderToHost(element(view), domHost(), documentBody());
