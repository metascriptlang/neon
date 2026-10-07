import { runApp } from "../../src/platform/native/host";
import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { Text, View } from "../../src/components/primitives";
import { TextAlign } from "../../src/render/style";
import { StatusBar } from "../../src/components/statusBar";
import { SafeAreaView } from "../../src/components/safeAreaView";
import { useSafeAreaInsets } from "../../src/render/environment";
import { NeonNode } from "../../src/render/node";
import { nmTeardown, nmSystemInsets, nmTextVisualY, nmTextWidth, nmLabelProp, nmHasLabel, nmAnyProp, nmViewsCreated, nmTagWithProp, nmTouch } from "./nativeBridgeMock.h";

test "the native host publishes how far the unsafe areas reach into its root, and a translucent StatusBar takes the root edge to edge" {
	const insets = useSafeAreaInsets();
	const [clear, setClear] = createSignal(false);
	const app = (): NeonNode => <SafeAreaView style={{ flex: 1 }}>
		<StatusBar translucent={clear()} />
		<Text>safe</Text>
	</SafeAreaView>;
	runApp(app);
	nmSystemInsets(47, 0, 34, 0);
	const inside = `${insets().top}/${insets().bottom} ${nmTextVisualY("safe")}`;
	setClear(true);
	const edge = `${insets().top}/${insets().bottom} ${nmTextVisualY("safe")}`;
	setClear(false);
	const back = `${insets().top}/${insets().bottom} ${nmTextVisualY("safe")}`;
	nmTeardown();
	nmSystemInsets(0, 0, 0, 0);
	assert inside === "0/0 0", "a root inside the safe area reports no insets: " + inside;
	assert edge === "47/34 47", "edge to edge, SafeAreaView pads by the reported insets: " + edge;
	assert back === "0/0 0", "back inside the safe area: " + back;
}

test "a native Text sends its textAlign to the label and a centred label spans its parent" {
	const [align, setAlign] = createSignal<string>("center");
	const app = (): NeonNode => <View style={{ width: 300 }}>
		<Text style={{ textAlign: align() as TextAlign }}>mid</Text>
		<Text>plain</Text>
	</View>;
	runApp(app);
	const centred = `${nmLabelProp("mid", "textAlign")} ${nmTextWidth("mid")}`;
	setAlign("right");
	const right = `${nmLabelProp("mid", "textAlign")} ${nmTextWidth("mid")}`;
	setAlign("left");
	const left = `${nmLabelProp("mid", "textAlign")} ${nmTextWidth("mid")}`;
	const plain = `${nmLabelProp("plain", "textAlign")} ${nmTextWidth("plain")}`;
	nmTeardown();
	assert centred === "center 300", "centred: " + centred;
	assert right === "right 300", "right: " + right;
	assert left === "left 26", "left keeps the text's own width: " + left;
	assert plain === "<unset> 43", "an unaligned label sends nothing: " + plain;
}

function anyProp(name: string): string {
	return nmAnyProp(name);
}

function labelProp(text: string, name: string): string {
	return nmLabelProp(text, name);
}

test "a nested native Text is a styled span of its outer label, and a pressable span takes the press" {
	const [name, setName] = createSignal("Ada");
	const [bold, setBold] = createSignal(true);
	let log = "";
	const field = "\u001f";
	const record = "\u001e";
	const app = (): NeonNode => <View>
		<Text style={{ color: "#ffffff", fontSize: 15 }}>Hi <Text style={{ fontWeight: bold() ? "bold" : "normal", color: "#ff0000" }}>{name()}</Text>, see <Text style={{ textDecorationLine: "underline" }} onPress={(): void => { log += "link;"; }}>terms</Text>.</Text>
	</View>;
	runApp(app);
	const shown = nmHasLabel("Hi Ada, see terms.");
	const spans = labelProp("Hi Ada, see terms.", "textSpans");
	const labels = nmViewsCreated();
	setName("Grace");
	const renamed = nmHasLabel("Hi Grace, see terms.");
	setBold(false);
	const plain = labelProp("Hi Grace, see terms.", "textSpans");
	const label = nmTagWithProp("textSpans", plain);
	const fields = plain.split(record)[3].split(field);
	const link = parseInt(fields[7]) as int32;
	nmTouch(link, 0);
	nmTouch(link, 1);
	nmTouch(link, 2);
	nmTeardown();
	assert shown === 1 && renamed === 1, `one label shows every run in order: ${shown} ${renamed}`;
	assert label !== link && link > 0, `the label carries a tag of its own, the span another: ${label} ${link}`;
	assert spans === "Hi " + field + "#ffffff" + field + "15" + field + "0" + field + "0" + field + "0" + field + "0" + field + "0"
		+ record + "Ada" + field + "#ff0000" + field + "15" + field + "1" + field + "0" + field + "0" + field + "0" + field + "0"
		+ record + ", see " + field + "#ffffff" + field + "15" + field + "0" + field + "0" + field + "0" + field + "0" + field + "0"
		+ record + "terms" + field + "#ffffff" + field + "15" + field + "0" + field + "0" + field + "1" + field + "0" + field + link.toString()
		+ record + "." + field + "#ffffff" + field + "15" + field + "0" + field + "0" + field + "0" + field + "0" + field + "0", "runs: " + spans;
	assert plain.indexOf("Grace" + field + "#ff0000" + field + "15" + field + "0") >= 0, "the span restyles: " + plain;
	assert log === "link;", "the pressed span fires its own onPress: " + log;
}
