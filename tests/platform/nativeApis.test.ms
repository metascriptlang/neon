import { runApp } from "../../src/platform/native/host";
import { View, Text } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { Platform } from "../../src/api/platform";
import { Dimensions } from "../../src/api/dimensions";
import { PixelRatio } from "../../src/api/pixelRatio";
import { AppState, AppStateStatus, useAppState } from "../../src/api/appState";
import { BackHandler } from "../../src/api/backHandler";
import { Alert } from "../../src/api/alert";
import { Linking, LinkingUrlEvent } from "../../src/api/linking";
import { Share, ShareAction } from "../../src/api/share";
import { Vibration } from "../../src/api/vibration";
import { Clipboard } from "../../src/api/clipboard";
import { AccessibilityInfo, useScreenReaderEnabled } from "../../src/api/accessibilityInfo";
import { Keyboard } from "../../src/api/keyboard";
import { nmAppReply, nmAppLog, nmAppLogClear, nmAppEvent, nmTeardown, nmTextWidth } from "./nativeBridgeMock.h";
import { flush } from "../../src/core/runtime";

const STATE: int32 = 0;
const BACK: int32 = 1;
const ALERT: int32 = 2;
const SCREEN_READER: int32 = 3;
const URL: int32 = 4;
const SHARE: int32 = 5;
const FIELD = "\u001f";

function mount(app: () => NeonNode): void {
	nmAppReply("platform", "17.5");
	flush();
	nmAppReply("isPad", "1");
	flush();
	nmAppReply("pixelRatio", "3");
	flush();
	nmAppReply("fontScale", "1.25");
	flush();
	nmAppReply("screen", "393" + FIELD + "852");
	flush();
	nmAppReply("appState", "active");
	flush();
	nmAppReply("a11y.screenReader", "0");
	flush();
	runApp(app);
	flush();
}

test "the native host publishes the platform constants, scale and screen when it starts" {
	mount((): NeonNode => <View><Text>{"ratio " + PixelRatio.get().toString()}</Text></View>);
	assert Platform.Version === "17.5", "version " + Platform.Version;
	assert Platform.isPad;
	assert PixelRatio.get() === 3;
	assert PixelRatio.getFontScale() === 1.25;
	const screen = Dimensions.get("screen");
	assert screen.width === 393 && screen.height === 852, "screen";
	assert nmTextWidth("ratio 3") > 0, "the app read the ratio at mount";
	nmTeardown();
	flush();
}

test "app state events reach currentState and a rendered accessor" {
	mount((): NeonNode => {
		const state = useAppState();
		return <View><Text>{"state " + (state() as string)}</Text></View>;
	});
	const seen: string[] = [];
	const subscription = AppState.addEventListener("change", (s: AppStateStatus): void => { seen.push(s as string); });
	nmAppEvent(STATE, "inactive");
	flush();
	nmAppEvent(STATE, "background");
	flush();
	assert AppState.currentState === "background";
	assert nmTextWidth("state background") > 0, "the label follows the state";
	nmAppEvent(STATE, "active");
	flush();
	subscription.remove();
	assert seen.join(",") === "inactive,background,active", seen.join(",");
	nmTeardown();
	flush();
}

test "a back press reports whether a BackHandler consumed it" {
	mount((): NeonNode => <View />);
	assert nmAppEvent(BACK, "") === 0, "no handler: the platform default runs";
	let presses = 0;
	const subscription = BackHandler.addEventListener("hardwareBackPress", (): boolean => {
		presses += 1;
		return presses === 1;
	});
	assert nmAppEvent(BACK, "") === 1, "the first press is consumed";
	assert nmAppEvent(BACK, "") === 0, "the second is not";
	subscription.remove();
	nmTeardown();
	flush();
}

test "Alert encodes title, message and buttons and runs the button the native dialog reports" {
	mount((): NeonNode => <View />);
	nmAppLogClear();
	flush();
	let chose = "";
	Alert.alert("Title", "Body", [
		{ text: "Cancel", style: "cancel", onPress: (): void => { chose = "cancel"; } },
		{ text: "OK", onPress: (): void => { chose = "ok"; } },
	]);
	const log: string = nmAppLog();
	const id = log.substring(6, log.indexOf(FIELD));
	assert log === "alert(" + id + FIELD + "Title" + FIELD + "Body" + FIELD + "0" + "\u001e" + "Cancel" + FIELD + "cancel" +
		"\u001e" + "OK" + FIELD + "default)", log;
	nmAppEvent(ALERT, id + FIELD + "1");
	flush();
	assert chose === "ok", chose;
	nmAppEvent(ALERT, id + FIELD + "0");
	flush();
	assert chose === "ok", "a settled alert ignores a second report";
	nmTeardown();
	flush();
}

test "Linking, Clipboard, Vibration and AccessibilityInfo go through the native command channel" {
	mount((): NeonNode => <View />);
	nmAppLogClear();
	flush();
	nmAppReply("linking.open", "1");
	flush();
	nmAppReply("linking.canOpen", "0");
	flush();
	nmAppReply("linking.initial", "neon://launch");
	flush();
	await Linking.openURL("https://example.com");
	flush();
	assert !(await Linking.canOpenURL("weird://x"));
	assert await Linking.getInitialURL() === "neon://launch";
	nmAppReply("clipboard.get", "pasted");
	flush();
	Clipboard.setString("copied");
	flush();
	assert await Clipboard.getString() === "pasted";
	Vibration.vibrate([0, 100, 50, 200]);
	Vibration.cancel();
	AccessibilityInfo.announceForAccessibility("Saved");
	Keyboard.dismiss();
	BackHandler.exitApp();
	const expected = [
		"linking.open(https://example.com)",
		"linking.canOpen(weird://x)",
		"linking.initial()",
		"clipboard.set(copied)",
		"clipboard.get()",
		"vibrate(0" + FIELD + "0,100,50,200)",
		"vibrate.cancel()",
		"a11y.announce(Saved)",
		"keyboard.dismiss()",
		"exitApp()",
	];
	const log: string = nmAppLog();
	assert log === expected.join(";"), log;
	nmAppReply("linking.open", "0");
	flush();
	let message = "";
	try {
		await Linking.openURL("nope://x");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Unable to open URL: nope://x", message;
	nmTeardown();
	flush();
}

test "Share resolves at once when the native side answers, else on the share event" {
	mount((): NeonNode => <View />);
	nmAppReply("share", "sharedAction");
	flush();
	const now: ShareAction = await Share.share({ message: "hi" });
	assert now.action === "sharedAction" && now.activityType === null;
	nmAppReply("share", "");
	flush();
	const later = Share.share({ message: "hi", url: "https://neon.dev" });
	nmAppEvent(SHARE, "sharedAction" + FIELD + "com.apple.UIKit.activity.Message");
	flush();
	const result = await later;
	assert result.action === "sharedAction" && result.activityType === "com.apple.UIKit.activity.Message";
	nmTeardown();
	flush();
}

test "screen reader and url events publish to their listeners" {
	mount((): NeonNode => <View />);
	const reader = useScreenReaderEnabled();
	const urls: string[] = [];
	const subscription = Linking.addEventListener("url", (e: LinkingUrlEvent): void => { urls.push(e.url); });
	nmAppEvent(SCREEN_READER, "1");
	flush();
	assert reader();
	nmAppEvent(SCREEN_READER, "0");
	flush();
	assert !reader();
	nmAppEvent(URL, "neon://open");
	flush();
	subscription.remove();
	assert urls.join(",") === "neon://open", urls.join(",");
	nmTeardown();
	flush();
}
