import { domHost, documentBody } from "../../src/platform/browser/dom";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { Pressable, Text, View } from "../../src/components/primitives";
import { createSignal } from "../../src/core/signal";
import { PanResponder, PanResponderGestureState } from "../../src/components/panResponder";
import { NeonEvent } from "../../src/render/event";

const [log, setLog] = createSignal("");
const say = (s: string): void => { setLog(log() + s); };
const pan = PanResponder.create({
	onMoveShouldSetPanResponder: (e: NeonEvent, g: PanResponderGestureState): boolean =>
		Math.abs(g.dx) > 10,
});
render(element(<View>
	<View {...pan.panHandlers}>
		<Pressable accessibilityLabel="Gesture" style={{ width: 200, height: 70 }}
			onPressIn={(): void => { say("in;"); }}
			onPressOut={(): void => { say("out;"); }}
			onLongPress={(): void => { say("long;"); }}
			delayLongPress={180}
			onPress={(): void => { say("press;"); }}><Text>Gesture</Text></Pressable>
	</View>
	<Pressable accessibilityLabel="Cheap" onPress={(): void => { say("cheap;"); }}>
		<Text>Cheap</Text>
	</Pressable>
	<span id="activation-log">{log()}</span>
</View>), domHost(), documentBody());
