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
import { AccessibilityInfo, AccessibilityAnnouncementFinishedEvent, useScreenReaderEnabled } from "../../src/api/accessibilityInfo";
import { Keyboard } from "../../src/api/keyboard";
import { installClipboardServices } from "../../src/api/clipboardServices";
import { nativeClipboardServices } from "../../src/platform/native/clipboard";
import { installLinkingServices } from "../../src/api/linkingServices";
import { nativeLinkingServices } from "../../src/platform/native/linking";
import { installVibrationServices } from "../../src/api/vibrationServices";
import { nativeVibrationServices } from "../../src/platform/native/vibration";
import { installAccessibilityServices } from "../../src/api/accessibilityServices";
import { nativeAccessibilityServices } from "../../src/platform/native/accessibilityInfo";
import { nmAppReply, nmAppLog, nmAppLogClear, nmAppEvent, nmTeardown, nmTextWidth } from "./nativeBridgeMock.h";

const STATE: int32 = 0;
const BACK: int32 = 1;
const ALERT: int32 = 2;
const SCREEN_READER: int32 = 3;
const URL: int32 = 4;
const SHARE: int32 = 5;
const ACCESSIBILITY: int32 = 15;
const FIELD = "\u001f";

function mount(app: () => NeonNode): void {
	nmAppReply("platform", "17.5");
	nmAppReply("isPad", "1");
	nmAppReply("pixelRatio", "3");
	nmAppReply("fontScale", "1.25");
	nmAppReply("screen", "393" + FIELD + "852");
	nmAppReply("appState", "active");
	nmAppReply("a11y.screenReader", "0");
	runApp(app);
	installClipboardServices(nativeClipboardServices);
	installLinkingServices(nativeLinkingServices);
	installVibrationServices(nativeVibrationServices);
	installAccessibilityServices(nativeAccessibilityServices);
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
}

test "app state events reach currentState and a rendered accessor" {
	mount((): NeonNode => {
		const state = useAppState();
		return <View><Text>{"state " + (state() as string)}</Text></View>;
	});
	const seen: string[] = [];
	const subscription = AppState.addEventListener("change", (s: AppStateStatus): void => { seen.push(s as string); });
	nmAppEvent(STATE, "inactive");
	nmAppEvent(STATE, "background");
	assert AppState.currentState === "background";
	assert nmTextWidth("state background") > 0, "the label follows the state";
	nmAppEvent(STATE, "active");
	subscription.remove();
	assert seen.join(",") === "inactive,background,active", seen.join(",");
	nmTeardown();
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
}

test "Alert encodes title, message and buttons and runs the button the native dialog reports" {
	mount((): NeonNode => <View />);
	nmAppLogClear();
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
	assert chose === "ok", chose;
	nmAppEvent(ALERT, id + FIELD + "0");
	assert chose === "ok", "a settled alert ignores a second report";
	nmTeardown();
}

test "Linking, Clipboard, Vibration and AccessibilityInfo go through the native command channel" {
	mount((): NeonNode => <View />);
	nmAppLogClear();
	nmAppReply("linking.open", "1");
	nmAppReply("linking.canOpen", "0");
	nmAppReply("linking.initial", "neon://launch");
	await Linking.openURL("https://example.com");
	assert !(await Linking.canOpenURL("weird://x"));
	assert await Linking.getInitialURL() === "neon://launch";
	nmAppReply("clipboard.get", "pasted");
	Clipboard.setString("copied");
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
	let message = "";
	try {
		await Linking.openURL("nope://x");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Unable to open URL: nope://x", message;
	nmTeardown();
}

test "Share resolves at once when the native side answers, else on the share event" {
	mount((): NeonNode => <View />);
	nmAppReply("share", "sharedAction");
	const now: ShareAction = await Share.share({ message: "hi" });
	assert now.action === "sharedAction" && now.activityType === null;
	nmAppReply("share", "");
	const later = Share.share({ message: "hi", url: "https://neon.dev" });
	nmAppEvent(SHARE, "sharedAction" + FIELD + "com.apple.UIKit.activity.Message");
	const result = await later;
	assert result.action === "sharedAction" && result.activityType === "com.apple.UIKit.activity.Message";
	nmTeardown();
}

test "screen reader and url events publish to their listeners" {
	mount((): NeonNode => <View />);
	const reader = useScreenReaderEnabled();
	const urls: string[] = [];
	const subscription = Linking.addEventListener("url", (e: LinkingUrlEvent): void => { urls.push(e.url); });
	nmAppEvent(SCREEN_READER, "1");
	assert reader();
	nmAppEvent(SCREEN_READER, "0");
	assert !reader();
	nmAppEvent(URL, "neon://open");
	subscription.remove();
	assert urls.join(",") === "neon://open", urls.join(",");
	nmTeardown();
}

test "AccessibilityInfo queries and announcements go to the native commands the platform expects" {
	mount((): NeonNode => <View />);
	const os = Platform.OS;
	nmAppReply("a11y.boldText", "1");
	nmAppReply("a11y.grayscale", "0");
	nmAppReply("a11y.invertColors", "1");
	nmAppReply("a11y.reduceTransparency", "1");
	nmAppReply("a11y.highTextContrast", "1");
	nmAppReply("a11y.darkerSystemColors", "1");
	nmAppReply("a11y.crossFade", "1");
	nmAppReply("a11y.accessibilityService", "1");
	nmAppReply("a11y.timeout", "9000");
	Platform.OS = "ios";
	nmAppLogClear();
	assert await AccessibilityInfo.isBoldTextEnabled();
	assert !(await AccessibilityInfo.isGrayscaleEnabled());
	assert await AccessibilityInfo.isInvertColorsEnabled();
	assert await AccessibilityInfo.isReduceTransparencyEnabled();
	assert await AccessibilityInfo.isDarkerSystemColorsEnabled();
	assert await AccessibilityInfo.prefersCrossFadeTransitions();
	assert !(await AccessibilityInfo.isHighTextContrastEnabled());
	assert await AccessibilityInfo.getRecommendedTimeoutMillis(3000) === 3000;
	AccessibilityInfo.announceForAccessibilityWithOptions("Queued", { queue: true });
	AccessibilityInfo.announceForAccessibilityWithOptions("Plain", {});
	const iosLog: string = nmAppLog();
	assert iosLog === "a11y.boldText();a11y.grayscale();a11y.invertColors();a11y.reduceTransparency();a11y.darkerSystemColors();a11y.crossFade();" +
		"a11y.announceQueue(1" + FIELD + "Queued);a11y.announce(Plain)", iosLog;
	Platform.OS = "android";
	nmAppLogClear();
	assert !(await AccessibilityInfo.isBoldTextEnabled());
	assert await AccessibilityInfo.isHighTextContrastEnabled();
	assert await AccessibilityInfo.isAccessibilityServiceEnabled();
	assert await AccessibilityInfo.getRecommendedTimeoutMillis(3000) === 9000;
	AccessibilityInfo.announceForAccessibilityWithOptions("Queued", { queue: true });
	const androidLog: string = nmAppLog();
	assert androidLog === "a11y.highTextContrast();a11y.accessibilityService();a11y.timeout(3000);a11y.announce(Queued)", androidLog;
	Platform.OS = os;
	nmTeardown();
}

test "accessibility events from the native side reach the change and announcement listeners" {
	mount((): NeonNode => <View />);
	const os = Platform.OS;
	Platform.OS = "ios";
	const seen: string[] = [];
	const bold = AccessibilityInfo.addEventListener("boldTextChanged", (on: boolean): void => { seen.push("bold " + on.toString()); });
	const darker = AccessibilityInfo.addEventListener("darkerSystemColorsChanged", (on: boolean): void => { seen.push("darker " + on.toString()); });
	const finished = AccessibilityInfo.addAnnouncementFinishedListener((e: AccessibilityAnnouncementFinishedEvent): void => {
		seen.push(e.announcement + " " + e.success.toString());
	});
	nmAppEvent(ACCESSIBILITY, "boldTextChanged" + FIELD + "1");
	nmAppEvent(ACCESSIBILITY, "darkerSystemColorsChanged" + FIELD + "0");
	nmAppEvent(ACCESSIBILITY, "announcementFinished" + FIELD + "Saved" + FIELD + "0");
	nmAppEvent(ACCESSIBILITY, "grayscaleChanged" + FIELD + "1");
	bold.remove();
	darker.remove();
	finished.remove();
	Platform.OS = os;
	assert seen.join(",") === "bold true,darker false,Saved false", seen.join(",");
	nmTeardown();
}
