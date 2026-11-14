import { View, Text, Pressable } from "../../../src/components/primitives";
import { createSignal } from "../../../src/core/signal";
import { onCleanup } from "../../../src/core/cleanup";
import { NeonNode } from "../../../src/render/hostTypes";
import { NeonEvent } from "../../../src/render/event";
import { element } from "../../../src/macros/ui/element";

let cleanups: int32 = 0;

export function cleanupCount(): int32 {
	return cleanups;
}

export function Card(title: string): NeonNode {
	const [count, setCount] = createSignal<int32>(0);
	onCleanup((): void => { cleanups += 1; });
	return element(
		<View style={{ flexDirection: "column", padding: 4 }}>
			<Text>{title}</Text>
			<Pressable onPress={(e: NeonEvent): void => { setCount(count() + 1); }}>
				<Text>{`pressed ${count()}`}</Text>
			</Pressable>
			<View onPointerDown={(e: NeonEvent): void => { e.stopPropagation(); }}>
				<Text>stop</Text>
			</View>
		</View>
	);
}

export function Ticker(): NeonNode {
	const [label, setLabel] = createSignal("waiting");
	setTimeout((): void => { setLabel("fired"); }, 20);
	return element(<Text>{label()}</Text>);
}

export function Lingering(): NeonNode {
	onCleanup((): void => {
		setTimeout((): void => { throw new Error("a lingering timer fired"); }, 20);
	});
	return element(<Text>lingering</Text>);
}
