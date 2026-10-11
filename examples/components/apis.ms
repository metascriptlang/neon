import { createSignal } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { View, Text, Pressable, TextInput } from "../../src/components/primitives";
import { useWindowDimensions, useColorScheme, useKeyboard } from "../../src/render/environment";
import { Platform } from "../../src/api/platform";
import { Dimensions } from "../../src/api/dimensions";
import { PixelRatio } from "../../src/api/pixelRatio";
import { AppState, AppStateStatus } from "../../src/api/appState";
import { BackHandler } from "../../src/api/backHandler";
import { Alert } from "../../src/api/alert";
import { Linking } from "../../src/api/linking";
import { Share } from "../../src/api/share";
import { Vibration } from "../../src/api/vibration";
import { Clipboard } from "../../src/api/clipboard";
import { AccessibilityInfo } from "../../src/api/accessibilityInfo";
import { Keyboard } from "../../src/api/keyboard";

const styles = createStyles({
	screen: { flex: 1, flexDirection: "column", gap: 6, padding: 12 },
	title: { color: "#cdd6f4", fontSize: 20, fontWeight: "bold" },
	status: { color: "#89b4fa", fontSize: 15 },
	buttons: { flexDirection: "row", flexWrap: "wrap", gap: 6 },
	button: { padding: 10, backgroundColor: "#45475a", color: "#cdd6f4", fontSize: 15 },
	input: { height: 44, padding: 8, backgroundColor: "#45475a", color: "#cdd6f4" },
});

function rounded(value: number): string {
	return (Math.round(value * 100) / 100).toString();
}

export function ApiDemo(): NeonNode {
	const window = useWindowDimensions();
	const scheme = useColorScheme();
	const keyboard = useKeyboard();
	const [history, setHistory] = createSignal<string>(AppState.currentState as string);
	const [backPresses, setBackPresses] = createSignal<int32>(0);
	const [alertChoice, setAlertChoice] = createSignal("none");
	const [shareResult, setShareResult] = createSignal("none");
	const [urlResult, setUrlResult] = createSignal("none");
	const [canOpen, setCanOpen] = createSignal("unknown");
	const [vibrations, setVibrations] = createSignal<int32>(0);
	const [copies, setCopies] = createSignal<int32>(0);
	const [pasted, setPasted] = createSignal("nothing");
	const [reader, setReader] = createSignal("unknown");

	const appState = AppState.addEventListener("change", (state: AppStateStatus): void => {
		setHistory(history() + ">" + (state as string));
	});
	const back = BackHandler.addEventListener("hardwareBackPress", (): boolean => {
		const consumed = backPresses() === 0;
		setBackPresses(backPresses() + 1);
		return consumed;
	});
	onCleanup((): void => {
		appState.remove();
		back.remove();
	});

	const share = async (): Promise<void> => {
		const result = await Share.share({ title: "Neon", message: "Hello from Neon", url: "https://neon.invalid/apis" });
		setShareResult(result.action);
	};
	const openUrl = async (): Promise<void> => {
		try {
			await Linking.openURL("tel:5550100");
			setUrlResult("opened");
		} catch (e) {
			setUrlResult("failed");
		}
	};
	const openSettings = async (): Promise<void> => {
		try {
			await Linking.openSettings();
			setUrlResult("settings");
		} catch (e) {
			setUrlResult("no settings");
		}
	};
	const checkUrl = async (): Promise<void> => {
		setCanOpen((await Linking.canOpenURL("https://example.com")) ? "yes" : "no");
		setReader((await AccessibilityInfo.isScreenReaderEnabled()) ? "on" : "off");
	};
	const paste = async (): Promise<void> => {
		setPasted(await Clipboard.getString());
	};
	checkUrl();

	return <View style={styles.screen}>
		<Text style={styles.title}>Neon APIs</Text>
		<Text style={styles.status}>{"os " + (Platform.OS as string) + " v" + Platform.Version.toString() + " pad " + (Platform.isPad ? "yes" : "no")}</Text>
		<Text style={styles.status}>{"window " + rounded(window().width) + "x" + rounded(window().height) + " scheme " + (scheme() as string)}</Text>
		<Text style={styles.status}>{"screen " + rounded(Dimensions.get("screen").width) + "x" + rounded(Dimensions.get("screen").height)}</Text>
		<Text style={styles.status}>{"ratio " + rounded(PixelRatio.get()) + " font " + rounded(PixelRatio.getFontScale()) + " 10pt " + PixelRatio.getPixelSizeForLayoutSize(10).toString() + "px"}</Text>
		<Text style={styles.status}>{"state " + history()}</Text>
		<Text style={styles.status}>{"back presses " + backPresses().toString()}</Text>
		<Text style={styles.status}>{"alert " + alertChoice()}</Text>
		<Text style={styles.status}>{"share " + shareResult()}</Text>
		<Text style={styles.status}>{"url " + urlResult() + " can https " + canOpen()}</Text>
		<Text style={styles.status}>{"vibrated " + vibrations().toString()}</Text>
		<Text style={styles.status}>{"pasted " + pasted()}</Text>
		<Text style={styles.status}>{"reader " + reader() + " keyboard " + (keyboard().visible ? "shown" : "hidden")}</Text>
		<View style={styles.buttons}>
			<Pressable style={styles.button} onPress={() => {
				Alert.alert("Neon alert", "Pick one", [
					{ text: "Cancel", style: "cancel", onPress: (): void => { setAlertChoice("cancel"); } },
					{ text: "Confirm", onPress: (): void => { setAlertChoice("confirm"); } },
				]);
			}}>show alert</Pressable>
			<Pressable style={styles.button} onPress={() => { share(); }}>share</Pressable>
			<Pressable style={styles.button} onPress={() => { openUrl(); }}>open url</Pressable>
			<Pressable style={styles.button} onPress={() => { openSettings(); }}>settings</Pressable>
			<Pressable style={styles.button} onPress={() => {
				Vibration.vibrate([0, 150, 100, 150]);
				setVibrations(vibrations() + 1);
			}}>vibrate</Pressable>
			<Pressable style={styles.button} onPress={() => {
				setCopies(copies() + 1);
				Clipboard.setString("neon-" + copies().toString());
			}}>copy</Pressable>
			<Pressable style={styles.button} onPress={() => { paste(); }}>paste</Pressable>
			<Pressable style={styles.button} onPress={() => { AccessibilityInfo.announceForAccessibility("Neon announcement"); }}>announce</Pressable>
			<Pressable style={styles.button} onPress={() => { Keyboard.dismiss(); }}>dismiss</Pressable>
		</View>
		<TextInput style={styles.input} placeholder="type here" />
	</View>;
}
