// A gallery of the RN core components: one scroll of sections, a status line
// the device drivers read, a Modal, a StatusBar toggle and a keyboard screen.

import { Accessor, createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, TextInput, ScrollView } from "../../src/components/primitives";
import { Button } from "../../src/components/button";
import { Switch } from "../../src/components/switch";
import { ActivityIndicator } from "../../src/components/activityIndicator";
import { ImageBackground } from "../../src/components/imageBackground";
import { TouchableOpacity, TouchableHighlight, TouchableWithoutFeedback } from "../../src/components/touchable";
import { Modal } from "../../src/components/modal";
import { StatusBar } from "../../src/components/statusBar";
import { SafeAreaView } from "../../src/components/safeAreaView";
import { KeyboardAvoidingView } from "../../src/components/keyboardAvoidingView";
import { RefreshControl } from "../../src/components/refreshControl";
import { Show } from "../../src/macros/ui/flow";
import { useKeyboard, useSafeAreaInsets } from "../../src/render/environment";

const LONG_TEXT = "Neon clamps this paragraph to two lines with numberOfLines, the way React Native's Text does, and ends it with an ellipsis instead of growing the row.";

function Section(props: { title: Accessor<string>; children: NeonNode }): NeonNode {
	return <View style={{ backgroundColor: "#1e1e2e", borderRadius: 10, padding: 12, gap: 8 }}>
		<Text style={{ color: "#89b4fa", fontSize: 13, fontWeight: "bold" }} accessibilityRole="header">{props.title().toUpperCase()}</Text>
		{props.children}
	</View>;
}

function KeyboardScreen(props: { back: () => void; say: (s: string) => void }): NeonNode {
	const keyboard = useKeyboard();
	const [inputY, setInputY] = createSignal<number>(-1);
	return <KeyboardAvoidingView behavior="padding" style={{ flex: 1 }}>
		<View style={{ flex: 1, padding: 16, gap: 8 }}>
			<Button title="Back to gallery" onPress={(e: NeonEvent): void => { props.back(); }} />
			<Text style={{ color: "#cdd6f4" }}>{`keyboard ${keyboard().visible ? Math.round(keyboard().height).toString() : "hidden"}`}</Text>
			<Text style={{ color: "#cdd6f4" }}>{`message at ${inputY()}`}</Text>
		</View>
		<TextInput placeholder="Message" accessibilityLabel="Message" blurOnSubmit={true}
			style={{ height: 44, margin: 12, paddingLeft: 10, backgroundColor: "#313244", color: "#cdd6f4", borderRadius: 8 }}
			onSubmitEditing={(e: NeonEvent): void => { props.say(`sent ${e.value}`); }}
			onLayout={(e: NeonEvent): void => { setInputY(Math.round(e.y)); }} />
	</KeyboardAvoidingView>;
}

export function GalleryApp(): NeonNode {
	const [status, setStatus] = createSignal("ready");
	const [presses, setPresses] = createSignal(0);
	const [modalOpen, setModalOpen] = createSignal(false);
	const [barHidden, setBarHidden] = createSignal(false);
	const [screen, setScreen] = createSignal("gallery");
	const [refreshing, setRefreshing] = createSignal(false);
	const [refreshes, setRefreshes] = createSignal(0);
	const [toggle, setToggle] = createSignal(false);
	const [notes, setNotes] = createSignal("");
	const [image, setImage] = createSignal("loading");
	const insets = useSafeAreaInsets();
	const say = (s: string): void => { setStatus(s); };
	const press = (what: string): void => {
		setPresses(presses() + 1);
		say(`${what} ${presses()}`);
	};
	const refresh = (): void => {
		setRefreshing(true);
		setTimeout((): void => {
			setRefreshes(refreshes() + 1);
			setRefreshing(false);
			say(`refreshed ${refreshes()}`);
		}, 600);
	};

	return <SafeAreaView style={{ flex: 1, backgroundColor: "#11111b" }}>
		<StatusBar barStyle="light-content" backgroundColor="#11111b" hidden={barHidden()} />
		<View style={{ padding: 12, gap: 2 }}>
			<Text style={{ color: "#cdd6f4", fontSize: 22, fontWeight: "bold" }} accessibilityRole="header">Neon gallery</Text>
			<Text style={{ color: "#a6e3a1", fontSize: 15 }}>{`status: ${status()}`}</Text>
			<Text style={{ color: "#6c7086", fontSize: 12 }}>{`insets ${insets().top}/${insets().bottom} · bar ${barHidden() ? "hidden" : "shown"} · image ${image()}`}</Text>
		</View>
		<Show when={screen() === "keyboard"}>
			<KeyboardScreen back={(): void => { setScreen("gallery"); say("back"); }} say={say} />
		</Show>
		<Show when={screen() === "gallery"}>
			<ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 12, gap: 12 }}
				refreshControl={<RefreshControl refreshing={refreshing()} onRefresh={refresh} tintColor="#89b4fa" colors={["#89b4fa"]} />}>
				<Section title="Button">
					<Button title="Press me" onPress={(e: NeonEvent): void => { press("button"); }} />
					<Button title="Disabled" disabled={true} onPress={(e: NeonEvent): void => { press("disabled"); }} />
				</Section>
				<Section title="Touchables">
					<TouchableOpacity style={{ padding: 12, backgroundColor: "#45475a", borderRadius: 8 }} onPress={(e: NeonEvent): void => { press("opacity"); }}>
						<Text style={{ color: "#cdd6f4" }}>Touchable opacity</Text>
					</TouchableOpacity>
					<TouchableHighlight underlayColor="#f38ba8" style={{ padding: 12, borderRadius: 8 }} onPress={(e: NeonEvent): void => { press("highlight"); }}>
						<Text style={{ color: "#cdd6f4" }}>Touchable highlight</Text>
					</TouchableHighlight>
					<TouchableWithoutFeedback onPress={(e: NeonEvent): void => { press("plain"); }}>
						<Text style={{ color: "#cdd6f4", padding: 12 }}>Touchable without feedback</Text>
					</TouchableWithoutFeedback>
				</Section>
				<Section title="Modal">
					<Button title="Open modal" onPress={(e: NeonEvent): void => { setModalOpen(true); }} />
				</Section>
				<Section title="Status bar">
					<Button title={barHidden() ? "Show status bar" : "Hide status bar"} onPress={(e: NeonEvent): void => {
						setBarHidden(!barHidden());
						say(barHidden() ? "status bar hidden" : "status bar shown");
					}} />
				</Section>
				<Section title="Keyboard">
					<Button title="Open keyboard screen" onPress={(e: NeonEvent): void => { setScreen("keyboard"); say("keyboard screen"); }} />
				</Section>
				<Section title="Text">
					<Text numberOfLines={2} style={{ color: "#cdd6f4", fontSize: 15 }}>{LONG_TEXT}</Text>
					<TextInput multiline={true} placeholder="Notes" accessibilityLabel="Notes" value={notes()}
						style={{ height: 88, padding: 8, backgroundColor: "#313244", color: "#cdd6f4", borderRadius: 8 }}
						onChangeText={(t: string): void => { setNotes(t); say(`notes ${t.length}`); }} />
				</Section>
				<Section title="Image background">
					<ImageBackground source={{ uri: "https://picsum.photos/id/29/600/240" }} resizeMode="cover"
						style={{ height: 120, justifyContent: "flex-end", padding: 8 }} imageStyle={{ borderRadius: 8 }}
						onLoad={(e: NeonEvent): void => { setImage("loaded"); }}
						onError={(e: NeonEvent): void => { setImage("failed"); }}>
						<Text style={{ color: "#ffffff", fontSize: 18, fontWeight: "bold" }}>Over the image</Text>
					</ImageBackground>
				</Section>
				<Section title="Controls">
					<View style={{ flexDirection: "row", alignItems: "center", gap: 12 }}>
						<Switch value={toggle()} onValueChange={(v: boolean): void => { setToggle(v); say(`switch ${v}`); }} accessibilityLabel="Gallery switch" />
						<ActivityIndicator animating={refreshing()} color="#89b4fa" />
					</View>
				</Section>
			</ScrollView>
		</Show>
		<Modal visible={modalOpen()} animationType="slide" transparent={true}
			onShow={(): void => { say("modal shown"); }}
			onRequestClose={(): void => { setModalOpen(false); say("modal closed by request"); }}>
			<View style={{ flex: 1, justifyContent: "center", padding: 24, backgroundColor: "#11111b" }}>
				<View style={{ backgroundColor: "#313244", borderRadius: 12, padding: 20, gap: 12 }}>
					<Text style={{ color: "#cdd6f4", fontSize: 20 }} accessibilityRole="header">Modal content</Text>
					<Button title="Close modal" onPress={(e: NeonEvent): void => { setModalOpen(false); say("modal closed"); }} />
				</View>
			</View>
		</Modal>
	</SafeAreaView>;
}
