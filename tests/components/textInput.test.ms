import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEventWith } from "../../src/render/host";
import { View, Text, Pressable, TextInput, TextInputHandle } from "../../src/components/primitives";
import { NeonEvent, neonEvent } from "../../src/render/event";

function typed(value: string): NeonEvent {
	const e = neonEvent("changetext");
	e.value = value;
	return e;
}

test "TextInput writes its RN props as attributes and routes typing and submit" {
	const [name, setName] = createSignal("Ada");
	let submitted = "";
	const root: MockNode = mockNode("root");
	render(element(<TextInput value={name()} placeholder="Name" secureTextEntry={false} maxLength={12}
		keyboardType="email-address" returnKeyType="next" autoCapitalize="none" accessibilityLabel="Email"
		onChangeText={(t: string): void => { setName(t); }}
		onSubmitEditing={(e: NeonEvent): void => { submitted = e.value; }} />), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><textinput value=\"Ada\" placeholder=\"Name\" secureTextEntry=\"false\" autoCapitalize=\"none\" maxLength=\"12\" keyboardType=\"email-address\" returnKeyType=\"next\" accessibilityLabel=\"Email\"></textinput></root>", "attributes: " + mockToString(root);
	const field = root.children[0];
	fireEventWith(field, "onChangeText", typed("Grace"));
	assert mockToString(root).indexOf("value=\"Grace\"") > 0, "controlled value follows the setter: " + mockToString(root);
	fireEventWith(field, "onSubmitEditing", typed("Grace"));
	assert submitted === "Grace", "submit carries the text: " + submitted;
}

test "a TextInput ref is a handle whose focus and blur go through the host and track isFocused" {
	const handles: TextInputHandle[] = [];
	let log = "";
	const root: MockNode = mockNode("root");
	render(element(<View>
		<TextInput ref={(h: TextInputHandle): void => { handles.push(h); }} returnKeyType="next"
			onSubmitEditing={(e: NeonEvent): void => { handles[1].focus(); }}
			onBlur={(e: NeonEvent): void => { log += "blur first;"; }} />
		<TextInput ref={(h: TextInputHandle): void => { handles.push(h); }}
			onFocus={(e: NeonEvent): void => { log += "focus second;"; }} />
	</View>), mockHost(), root as unknown as HostNode);
	assert handles.length === 2, "both refs fired";
	handles[0].focus();
	assert handles[0].isFocused() && !handles[1].isFocused(), "first focused";
	fireEventWith(root.children[0].children[0], "onSubmitEditing", typed(""));
	handles[0].blur();
	assert !handles[0].isFocused() && handles[1].isFocused(), "focus moved to the second field";
	assert log === "focus second;blur first;", "events: " + log;
}

test "accessibility props reach every primitive as attributes" {
	const root: MockNode = mockNode("root");
	render(element(<View accessible={true} accessibilityLabel="Card" accessibilityRole="summary">
		<Text accessibilityRole="header">Title</Text>
		<Pressable accessibilityLabel="Save" accessibilityHint="Saves the form" accessibilityRole="button" onPress={() => {}}>Save</Pressable>
	</View>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><view accessible=\"true\" accessibilityLabel=\"Card\" accessibilityRole=\"summary\"><text accessibilityRole=\"header\">Title</text><pressable accessible=\"true\" accessibilityLabel=\"Save\" accessibilityHint=\"Saves the form\" accessibilityRole=\"button\">Save</pressable></view></root>", "attributes: " + mockToString(root);
}

test "a multiline TextInput is RN's separate multiline input, chosen once from its first value" {
	const root: MockNode = mockNode("root");
	render(element(<View><TextInput multiline={true} placeholder="Notes" /><TextInput multiline={false} /></View>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><view><multilinetextinput placeholder=\"Notes\" multiline=\"true\"></multilinetextinput><textinput multiline=\"false\"></textinput></view></root>", "shape: " + mockToString(root);
}
