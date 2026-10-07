import { runApp } from "../../src/platform/native/host";
import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { Text, View, TextInput, TextSelection, Pressable } from "../../src/components/primitives";
import { NeonEvent } from "../../src/render/event";
import { TextAlign } from "../../src/render/style";
import { StatusBar } from "../../src/components/statusBar";
import { SafeAreaView } from "../../src/components/safeAreaView";
import { useSafeAreaInsets } from "../../src/render/environment";
import { NeonNode } from "../../src/render/node";
import { nmTeardown, nmSystemInsets, nmTextVisualY, nmTextWidth, nmLabelProp, nmHasLabel, nmAnyProp, nmViewsCreated, nmTagWithProp, nmTouch, nmLastInputTag, nmLayoutHeight, nmControl, nmProp, nmAppLog, nmAppLogClear, nmAppEvent, nmLastPressableTag } from "./nativeBridgeMock.h";
import { ImageLoader } from "../../src/components/image";
import { Dialog } from "../../src/components/dialog";

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

function appLog(): string {
	return nmAppLog();
}

function prop(tag: int32, name: string): string {
	return nmProp(tag, name);
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

test "a native multiline TextInput without a height grows with its text up to maxHeight" {
	const [notes, setNotes] = createSignal("");
	const app = (): NeonNode => <View style={{ width: 200 }}>
		<TextInput multiline={true} value={notes()} onChangeText={(t: string): void => { setNotes(t); }} style={{ maxHeight: 80 }} onLayout={(e: NeonEvent): void => {}} />
		<TextInput multiline={true} value={notes()} style={{ height: 40 }} />
	</View>;
	runApp(app);
	const field = nmLastInputTag();
	const empty = nmLayoutHeight(field);
	nmControl(field, 0, "a line of text that wraps");
	const typed = nmLayoutHeight(field);
	setNotes("a very long note that wraps over many lines in a two hundred point wide field");
	const capped = nmLayoutHeight(field);
	setNotes("");
	const cleared = nmLayoutHeight(field);
	nmTeardown();
	assert empty === 21 && typed === 42, `one line, then two: ${empty} ${typed}`;
	assert capped === 80, "maxHeight caps the growth: " + capped.toString();
	assert cleared === 21, "shrinks back: " + cleared.toString();
}

test "a native TextInput writes its selection and reports the native one" {
	const [sel, setSel] = createSignal<TextSelection>({ start: 1, end: 3 });
	let seen = "";
	const app = (): NeonNode => <View>
		<TextInput value="hello" selection={sel()} onSelectionChange={(s: TextSelection): void => { seen = `${s.start}-${s.end}`; }} />
	</View>;
	runApp(app);
	const field = nmLastInputTag();
	const written = prop(field, "selection");
	setSel({ start: 4, end: null });
	const caret = prop(field, "selection");
	nmControl(field, 9, "2,5");
	nmTeardown();
	assert written === "1,3" && caret === "4,4", `written ${written} ${caret}`;
	assert seen === "2-5", "reported: " + seen;
}

test "ImageLoader.getSize on the native host asks the app channel and settles on its image event" {
	const app = (): NeonNode => <View />;
	runApp(app);
	nmAppLogClear();
	let got = "";
	ImageLoader.getSize("https://x/a.png", (w: number, h: number): void => { got = `${w}x${h}`; }, (e: Error): void => { got = "failed " + e.message; });
	const log = appLog();
	const id = log.substring(log.indexOf("(") + 1, log.indexOf("\u001f"));
	nmAppEvent(8, id + "\u001f600\u001f240\u001f");
	const ok = got;
	ImageLoader.getSize("https://x/b.png", (w: number, h: number): void => { got = "wrong"; }, (e: Error): void => { got = "failed " + e.message; });
	const second = appLog();
	const next = second.substring(second.lastIndexOf("(") + 1, second.lastIndexOf("\u001f"));
	nmAppEvent(8, next + "\u001f0\u001f0\u001fHTTP 404");
	nmTeardown();
	assert log === "image.size(" + id + "\u001fhttps://x/a.png)", "asked: " + log;
	assert ok === "600x240", "size: " + ok;
	assert got === "failed HTTP 404", "failure: " + got;
}

test "a native Pressable writes hitSlop per edge and its Android ripple through the prop channel" {
	const [bottom, setBottom] = createSignal(8);
	const app = (): NeonNode => <View>
		<Pressable hitSlop={{ top: 4, bottom: bottom() }} android_ripple={{ color: "#33000000" }} onPress={(e: NeonEvent): void => {}}><Text>edge</Text></Pressable>
	</View>;
	runApp(app);
	const button = nmLastPressableTag();
	const first = prop(button, "hitSlop");
	setBottom(12);
	const second = prop(button, "hitSlop");
	const ripple = prop(button, "androidRipple");
	nmTeardown();
	assert first === "4,0,8,0" && second === "4,0,12,0", `per edge: ${first} ${second}`;
	assert ripple === "#33000000,false,", "ripple: " + ripple;
}

test "the native back press closes a shown Dialog through BackHandler" {
	const [open, setOpen] = createSignal(true);
	let log = "";
	const app = (): NeonNode => <View style={{ flex: 1 }}>
		<Dialog visible={open()} title="Leave?" onDismiss={(): void => { log += "dismiss;"; setOpen(false); }} />
	</View>;
	runApp(app);
	const consumed = nmAppEvent(1, "");
	const after = nmAppEvent(1, "");
	nmTeardown();
	assert consumed === 1 && log === "dismiss;", `consumed and dismissed: ${consumed} ${log}`;
	assert after === 0, "the next back press goes to the platform: " + after.toString();
}
