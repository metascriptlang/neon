// A gallery of the RN core components: one scroll of sections, a status line
// the device drivers read, a Modal, a StatusBar toggle and a keyboard screen.

import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, TextInput, ScrollView, Pressable, TextSelection } from "../../src/components/primitives";
import { Image, ImageLoader } from "../../src/components/image";
import { Dialog, DialogAction } from "../../src/components/dialog";
import { StyleSheet } from "../../src/api/styleSheet";
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

const TILE = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==";
const PHOTO = "https://picsum.photos/id/29/600/240";

// The React Native parity screen: safe-area insets, textAlign, nested Text spans, multiline
// growth and selection, Image extras, StyleSheet, Pressable hitSlop and android_ripple, and a
// Dialog the Android back button closes.
function ParityScreen(props: { back: () => void; say: (s: string) => void; edge: Accessor<boolean>; setEdge: (on: boolean) => void }): NeonNode {
	const [growH, setGrowH] = createSignal<number>(0);
	const [selected, setSelected] = createSignal("none");
	const [size, setSize] = createSignal("pending");
	const [dialog, setDialog] = createSignal(false);
	const say = props.say;
	ImageLoader.getSize(PHOTO, (w: number, h: number): void => { setSize(`${w}x${h}`); }, (e: Error): void => { setSize("failed"); });
	return <View style={{ flex: 1 }}>
		<ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 12, paddingBottom: 240, gap: 12 }}>
			<Button title="Back to gallery" onPress={(e: NeonEvent): void => { props.back(); }} />
			<Section title="Safe area">
				<Button title={props.edge() ? "Inside safe area" : "Edge to edge"} onPress={(e: NeonEvent): void => {
					props.setEdge(!props.edge());
					say(props.edge() ? "edge to edge" : "inside safe area");
				}} />
			</Section>
			<Section title="Text">
				<Text style={{ color: "#cdd6f4", textAlign: "center", backgroundColor: "#313244" }}>centred</Text>
				<Text style={{ color: "#cdd6f4", fontSize: 15 }} onPress={(e: NeonEvent): void => { say("text pressed"); }}><Text style={{ color: "#89b4fa", fontWeight: "bold", textDecorationLine: "underline" }} onPress={(e: NeonEvent): void => { say("terms pressed"); }}>Terms</Text> apply to <Text style={{ fontStyle: "italic", color: "#f38ba8" }}>this</Text> gallery.</Text>
			</Section>
			<Section title="Text input">
				<TextInput multiline={true} placeholder="Grows with its text" accessibilityLabel="Grow"
					style={{ maxHeight: 120, padding: 8, backgroundColor: "#313244", color: "#cdd6f4", borderRadius: 8 }}
					onLayout={(e: NeonEvent): void => { setGrowH(Math.round(e.height)); }} />
				<Text style={{ color: "#cdd6f4" }}>{`grow ${growH()}`}</Text>
				<TextInput value="hello world" accessibilityLabel="Selectable" selection={{ start: 6, end: 11 }}
					style={{ height: 40, paddingLeft: 8, backgroundColor: "#313244", color: "#cdd6f4", borderRadius: 8 }}
					onSelectionChange={(sel: TextSelection): void => { setSelected(`${sel.start}-${sel.end}`); }} />
				<Text style={{ color: "#cdd6f4" }}>{`selection ${selected()}`}</Text>
			</Section>
			<Section title="Image">
				<Image source={{ uri: PHOTO }} defaultSource={{ uri: TILE }} blurRadius={4} accessibilityLabel="Blurred photo" style={{ height: 80, borderRadius: 8 }} />
				<Image source={{ uri: TILE }} resizeMode="repeat" accessibilityLabel="Tiled" style={{ height: 30 }} />
				<Text style={{ color: "#cdd6f4" }}>{`size ${size()}`}</Text>
			</Section>
			<Section title="StyleSheet">
				<View style={{ height: 40, justifyContent: "center", padding: 8 }}>
					<View style={[StyleSheet.absoluteFill, { backgroundColor: "#45475a", borderRadius: 8 }]} />
					<Text style={{ color: "#cdd6f4" }}>absolute fill</Text>
				</View>
				<View style={{ height: StyleSheet.hairlineWidth, backgroundColor: "#cdd6f4" }} />
				<Text style={{ color: "#cdd6f4" }}>{`hairline ${Math.round(StyleSheet.hairlineWidth * 1000) / 1000}`}</Text>
			</Section>
			<Section title="Pressable">
				<View style={{ flexDirection: "row", padding: 32 }}>
					<Pressable hitSlop={24} android_ripple={{ color: "#5589b4fa", borderless: true }} accessibilityLabel="Slop target"
						style={{ width: 24, height: 24, borderRadius: 12, backgroundColor: "#89b4fa" }}
						onPress={(e: NeonEvent): void => { say("slop pressed"); }} />
				</View>
			</Section>
			<Section title="Dialog">
				<Button title="Open dialog" onPress={(e: NeonEvent): void => { setDialog(true); say("dialog open"); }} />
			</Section>
		</ScrollView>
		<Dialog visible={dialog()} title="Parity dialog" onDismiss={(): void => { setDialog(false); say("dialog dismissed"); }}
			actions={<DialogAction label="Close" onPress={(): void => { setDialog(false); say("dialog closed"); }} />}>
			<Text style={{ color: "#1d1b20" }}>Android back closes this dialog.</Text>
		</Dialog>
	</View>;
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
	const [edge, setEdge] = createSignal(false);
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
		<StatusBar barStyle="light-content" backgroundColor="#11111b" hidden={barHidden()} translucent={edge()} />
		<View style={{ padding: 12, gap: 2 }}>
			<Text style={{ color: "#cdd6f4", fontSize: 22, fontWeight: "bold" }} accessibilityRole="header">Neon gallery</Text>
			<Text style={{ color: "#a6e3a1", fontSize: 15 }}>{`status: ${status()}`}</Text>
			<Text style={{ color: "#6c7086", fontSize: 12 }}>{`insets ${insets().top}/${insets().bottom} · bar ${barHidden() ? "hidden" : "shown"} · image ${image()}`}</Text>
		</View>
		<Show when={screen() === "keyboard"}>
			<KeyboardScreen back={(): void => { setScreen("gallery"); say("back"); }} say={say} />
		</Show>
		<Show when={screen() === "parity"}>
			<ParityScreen back={(): void => { setScreen("gallery"); say("back"); }} say={say} edge={accessor((): boolean => edge())} setEdge={(on: boolean): void => { setEdge(on); }} />
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
				<Section title="React Native parity">
					<Button title="Open parity screen" onPress={(e: NeonEvent): void => { setScreen("parity"); say("parity screen"); }} />
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
