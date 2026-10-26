import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, TextInput, Pressable } from "../../src/components/primitives";
import { InputAccessoryView } from "../../src/components/inputAccessoryView";

export function InputAccessoryDemo(): NeonNode {
	const [taps, setTaps] = createSignal(0 as int32);
	const [text, setText] = createSignal("");
	return <View style={{ flex: 1, padding: 16, paddingTop: 80 }}>
		<TextInput accessibilityLabel="Message" placeholder="Message" value={text()} onChangeText={(t: string): void => { setText(t); }}
			inputAccessoryViewID="bar" style={{ height: 44, borderWidth: 1, borderColor: "#888888", padding: 8, color: "#ffffff" }} />
		<Text accessibilityLabel="Taps">{`accessory taps: ${taps()}`}</Text>
		<Text accessibilityLabel="Typed">{`typed: ${text()}`}</Text>
		<InputAccessoryView nativeID="bar" backgroundColor="#303030">
			<Pressable accessibilityLabel="Accessory Send" style={{ height: 44, justifyContent: "center", alignItems: "center" }}
				onPress={(e: NeonEvent): void => { setTaps(taps() + 1); }}>
				<Text>Send</Text>
			</Pressable>
		</InputAccessoryView>
	</View>;
}
