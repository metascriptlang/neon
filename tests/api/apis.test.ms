import { createRoot } from "../../src/core/owner";
import { createEffect } from "../../src/core/effect";
import { publishWindow, publishKeyboard, publishColorScheme } from "../../src/render/environment";
import { ALERT_DISMISSED, installAppServices } from "../../src/api/services";
import { Platform } from "../../src/api/platform";
import { Dimensions, DimensionsChange, publishScale, publishScreen } from "../../src/api/dimensions";
import { PixelRatio } from "../../src/api/pixelRatio";
import { Appearance, AppearancePreferences } from "../../src/api/appearance";
import { Keyboard, KeyboardEvent } from "../../src/api/keyboard";
import { AppState, AppStateStatus, useAppState, publishAppState } from "../../src/api/appState";
import { BackHandler, dispatchHardwareBackPress } from "../../src/api/backHandler";
import { Alert } from "../../src/api/alert";
import { Linking, LinkingUrlEvent, publishUrl } from "../../src/api/linking";
import { Share, ShareAction } from "../../src/api/share";
import { Vibration } from "../../src/api/vibration";
import { Clipboard } from "../../src/api/clipboard";
import { AccessibilityInfo, publishScreenReader } from "../../src/api/accessibilityInfo";
import { FakeServices } from "./fakeServices";

test "Platform names the compile-time OS and selects its entry, then native, then default" {
	when (js) {
		assert Platform.OS === "web", "js is web";
		assert Platform.select<string>({ web: "w", native: "n", default: "d" }) === "w";
		assert Platform.select<string>({ ios: "i", native: "n", default: "d" }) === "d", "web is not native";
	} else {
		assert Platform.OS === "macos", "a desktop test build is macos";
		assert Platform.select<string>({ macos: "m", default: "d" }) === "m";
		assert Platform.select<string>({ ios: "i", default: "d" }) === "d";
	}
	assert Platform.select<int32>({ android: 1, ios: 2, macos: 3, web: 3, default: 4 }) === 3;
}

test "Platform.select with no matching entry and no default throws, naming the OS" {
	let message = "";
	try {
		Platform.select<string>({ android: "a" });
	} catch (e) {
		message = (e as Error).message;
	}
	assert message.startsWith("Platform.select: no entry for "), message;
}

test "Dimensions and PixelRatio read the host's published window, screen and scale" {
	publishWindow(390, 844);
	publishScale(3, 1.5);
	publishScreen(0, 0);
	const window = Dimensions.get("window");
	assert window.width === 390 && window.height === 844, "window";
	assert window.scale === 3 && window.fontScale === 1.5, "scale";
	const screen = Dimensions.get("screen");
	assert screen.width === 390 && screen.height === 844, "an unknown screen reports the window";
	publishScreen(400, 900);
	assert Dimensions.get("screen").height === 900, "the published screen";
	assert PixelRatio.get() === 3;
	assert PixelRatio.getFontScale() === 1.5;
	assert PixelRatio.getPixelSizeForLayoutSize(10.2) === 31, "round(10.2 * 3)";
	assert PixelRatio.roundToNearestPixel(8.4) === 25.0 / 3.0, "round(8.4 * 3) / 3";
}

test "Dimensions change listeners fire on a change only, until removed" {
	publishWindow(390, 844);
	const seen: string[] = [];
	const subscription = Dimensions.addEventListener("change", (change: DimensionsChange): void => {
		seen.push(change.window.width.toString() + "x" + change.window.height.toString());
	});
	assert seen.length === 0, "no call with the current value";
	publishWindow(844, 390);
	assert seen.join(",") === "844x390", seen.join(",");
	subscription.remove();
	publishWindow(390, 844);
	assert seen.length === 1, "removed";
}

test "Appearance reads and follows the published color scheme" {
	publishColorScheme("light");
	assert Appearance.getColorScheme() === "light";
	const seen: string[] = [];
	const subscription = Appearance.addChangeListener((p: AppearancePreferences): void => { seen.push(p.colorScheme as string); });
	publishColorScheme("dark");
	assert Appearance.getColorScheme() === "dark";
	publishColorScheme("dark");
	publishColorScheme("light");
	subscription.remove();
	assert seen.join(",") === "dark,light", seen.join(",");
}

test "Keyboard show and hide listeners follow the published height; dismiss goes to the host" {
	const fake = new FakeServices();
	fake.install();
	publishWindow(400, 800);
	publishKeyboard(0);
	const shows: string[] = [];
	const hides: string[] = [];
	const frameHeights: string[] = [];
	const shown = Keyboard.addListener("keyboardDidShow", (e: KeyboardEvent): void => {
		shows.push(e.endCoordinates.height.toString() + "@" + e.endCoordinates.screenY.toString());
	});
	const hidden = Keyboard.addListener("keyboardWillHide", (e: KeyboardEvent): void => { hides.push(e.endCoordinates.height.toString()); });
	const frames = Keyboard.addListener("keyboardDidChangeFrame", (e: KeyboardEvent): void => {
		frameHeights.push(e.endCoordinates.height.toString());
	});
	publishKeyboard(300);
	assert Keyboard.isVisible();
	const metrics = Keyboard.metrics();
	assert metrics !== null && metrics.height === 300, "metrics";
	publishKeyboard(320);
	publishKeyboard(0);
	assert !Keyboard.isVisible();
	assert Keyboard.metrics() === null;
	assert shows.join(",") === "300@500", shows.join(",");
	assert hides.join(",") === "0", hides.join(",");
	assert frameHeights.join(",") === "300,320,0", frameHeights.join(",");
	shown.remove();
	hidden.remove();
	frames.remove();
	Keyboard.dismiss();
	assert fake.joined() === "dismissKeyboard", fake.joined();
}

test "AppState follows the published state for currentState, the accessor and change listeners" {
	publishAppState("active");
	const state = useAppState();
	const changes: string[] = [];
	const blurs: string[] = [];
	const change = AppState.addEventListener("change", (s: AppStateStatus): void => { changes.push(s as string); });
	const blur = AppState.addEventListener("blur", (s: AppStateStatus): void => { blurs.push(s as string); });
	let tracked = "";
	const dispose = createRoot((d: () => void): () => void => {
		createEffect((): void => { tracked += (state() as string) + ";"; });
		return d;
	});
	publishAppState("inactive");
	assert AppState.currentState === "inactive";
	publishAppState("background");
	publishAppState("background");
	publishAppState("active");
	change.remove();
	blur.remove();
	dispose();
	publishAppState("background");
	assert changes.join(",") === "inactive,background,active", changes.join(",");
	assert blurs.join(",") === "inactive,background", blurs.join(",");
	assert tracked === "active;inactive;background;active;", tracked;
	assert AppState.currentState === "background";
	publishAppState("active");
}

test "BackHandler runs the newest handler first and stops at the first that consumes the press" {
	const order: string[] = [];
	const first = BackHandler.addEventListener("hardwareBackPress", (): boolean => {
		order.push("first");
		return true;
	});
	const second = BackHandler.addEventListener("hardwareBackPress", (): boolean => {
		order.push("second");
		return false;
	});
	assert dispatchHardwareBackPress(), "first consumes";
	assert order.join(",") === "second,first", order.join(",");
	first.remove();
	assert !dispatchHardwareBackPress(), "nobody consumes: the platform default runs";
	second.remove();
	assert !dispatchHardwareBackPress();
	const fake = new FakeServices();
	fake.install();
	BackHandler.exitApp();
	assert fake.joined() === "exitApp";
}

test "Alert hands the host its buttons and runs the chosen one's onPress, or onDismiss" {
	const fake = new FakeServices();
	fake.install();
	let chose = "";
	Alert.alert("Delete?", "It cannot be undone", [
		{ text: "Cancel", style: "cancel", onPress: (): void => { chose = "cancel"; } },
		{ text: "Delete", style: "destructive", onPress: (): void => { chose = "delete"; } },
	], { cancelable: true, onDismiss: (): void => { chose = "dismissed"; } });
	assert fake.alerts.length === 1;
	const request = fake.alerts[0];
	assert request.title === "Delete?" && request.message === "It cannot be undone";
	assert request.cancelable;
	assert request.buttons.length === 2;
	assert request.buttons[0].text === "Cancel" && request.buttons[0].style === "cancel";
	assert request.buttons[1].style === "destructive";
	request.done(1);
	assert chose === "delete", chose;
	request.done(ALERT_DISMISSED);
	assert chose === "dismissed", chose;

	Alert.alert("Saved");
	const plain = fake.alerts[1];
	assert plain.message === "" && !plain.cancelable;
	assert plain.buttons.length === 1 && plain.buttons[0].text === "OK" && plain.buttons[0].style === "default";
	plain.done(0);
}

test "an API without installed services throws, naming the API" {
	installAppServices(null);
	let message = "";
	try {
		Vibration.vibrate();
	} catch (e) {
		message = (e as Error).message;
	}
	assert message.startsWith("Vibration.vibrate: no host has installed app services"), message;
}

test "Vibration turns a duration into one pause-vibrate step and passes a pattern through" {
	const fake = new FakeServices();
	fake.install();
	Vibration.vibrate();
	Vibration.vibrate(250);
	Vibration.vibrate([0, 100, 50, 100], true);
	Vibration.cancel();
	assert fake.joined() === "vibrate 0 400;vibrate 0 250;vibrate 0 100 50 100 repeat;cancelVibration", fake.joined();
}

test "Linking opens, checks and reports urls through the host, and rejects what it cannot open" {
	const fake = new FakeServices();
	fake.install();
	await Linking.openURL("https://example.com");
	assert await Linking.canOpenURL("tel:123");
	assert await Linking.getInitialURL() === null, "no launch url";
	fake.initial = "neon://start";
	assert await Linking.getInitialURL() === "neon://start";
	fake.openable = false;
	let message = "";
	try {
		await Linking.openURL("nope://x");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Unable to open URL: nope://x", message;
	assert !(await Linking.canOpenURL("nope://x"));
	const urls: string[] = [];
	const subscription = Linking.addEventListener("url", (e: LinkingUrlEvent): void => { urls.push(e.url); });
	publishUrl("neon://a");
	subscription.remove();
	publishUrl("neon://b");
	assert urls.join(",") === "neon://a", urls.join(",");
	assert fake.joined() === "openURL https://example.com;canOpenURL tel:123;openURL nope://x;canOpenURL nope://x", fake.joined();
}

test "Share resolves with the action the host reports" {
	const fake = new FakeServices();
	fake.install();
	const pending = Share.share({ message: "hello", url: "https://neon.dev" }, { dialogTitle: "Send" });
	assert fake.shares.length === 1;
	fake.shares[0].done("sharedAction", "com.apple.UIKit.activity.CopyToPasteboard");
	const result: ShareAction = await pending;
	assert result.action === Share.sharedAction, result.action;
	assert result.activityType === "com.apple.UIKit.activity.CopyToPasteboard";
	assert fake.joined() === "share Send|hello|https://neon.dev", fake.joined();

	const dismissed = Share.share({ title: "T", message: "m" });
	fake.shares[1].done("dismissedAction", "");
	const second = await dismissed;
	assert second.action === Share.dismissedAction && second.activityType === null;
	assert fake.log[1] === "share T|m|", fake.log[1];
}

test "Share without a message or url rejects" {
	const fake = new FakeServices();
	fake.install();
	let message = "";
	try {
		await Share.share({ title: "only a title" });
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Share.share: at least one of message and url is required", message;
	assert fake.shares.length === 0;
}

test "Clipboard round-trips through the host" {
	const fake = new FakeServices();
	fake.install();
	assert !(await Clipboard.hasString());
	Clipboard.setString("copied");
	assert await Clipboard.getString() === "copied";
	assert await Clipboard.hasString();
}

test "AccessibilityInfo asks the host, follows the published screen reader and announces" {
	const fake = new FakeServices();
	fake.install();
	fake.screenReader = true;
	assert await AccessibilityInfo.isScreenReaderEnabled();
	assert !(await AccessibilityInfo.isReduceMotionEnabled());
	publishScreenReader(false);
	const seen: string[] = [];
	const subscription = AccessibilityInfo.addEventListener("screenReaderChanged", (on: boolean): void => {
		seen.push(on ? "on" : "off");
	});
	publishScreenReader(true);
	publishScreenReader(false);
	subscription.remove();
	publishScreenReader(true);
	assert seen.join(",") === "on,off", seen.join(",");
	AccessibilityInfo.announceForAccessibility("Saved");
	assert fake.joined() === "announce Saved", fake.joined();
	publishScreenReader(false);
}
