import { domHost, documentBody } from "../../src/platform/browser/dom";
import { NeonNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { TextInput, TextInputHandle, View } from "../../src/components/primitives";
import { Platform } from "../../src/api/platform";
import { Dimensions } from "../../src/api/dimensions";
import { PixelRatio } from "../../src/api/pixelRatio";
import { AppState, AppStateStatus } from "../../src/api/appState";
import { Alert } from "../../src/api/alert";
import { Linking } from "../../src/api/linking";
import { Share } from "../../src/api/share";
import { Vibration } from "../../src/api/vibration";
import { Clipboard } from "../../src/api/clipboard";
import { AccessibilityInfo } from "../../src/api/accessibilityInfo";
import { Keyboard } from "../../src/api/keyboard";

extern function js(code: cstring): string from "String((0, eval)(#))";

function mount(): void {
	render(element(<View />), domHost(), documentBody());
}

test "the DOM host installs app services: web platform, the page's pixel ratio and screen" {
	mount();
	assert Platform.OS === "web";
	assert PixelRatio.get().toString() === js("window.devicePixelRatio"), "ratio " + PixelRatio.get().toString();
	assert Dimensions.get("screen").width.toString() === js("window.screen.width");
	assert AppState.currentState === "active";
}

test "AppState follows the page's visibility" {
	mount();
	const seen: string[] = [];
	const subscription = AppState.addEventListener("change", (s: AppStateStatus): void => { seen.push(s as string); });
	js("Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' }); document.dispatchEvent(new Event('visibilitychange'))");
	assert AppState.currentState === "background";
	js("Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' }); document.dispatchEvent(new Event('visibilitychange'))");
	subscription.remove();
	assert AppState.currentState === "active";
	assert seen.join(",") === "background,active", seen.join(",");
}

test "Alert uses window.confirm for two buttons and window.alert for one" {
	mount();
	js("window.__asked = []; window.confirm = (t) => { window.__asked.push(t); return window.__answer; }; window.alert = (t) => { window.__asked.push('alert:' + t); }");
	let chose = "";
	js("window.__answer = true");
	Alert.alert("Delete?", "Gone for good", [
		{ text: "Cancel", style: "cancel", onPress: (): void => { chose = "cancel"; } },
		{ text: "Delete", style: "destructive", onPress: (): void => { chose = "delete"; } },
	]);
	assert chose === "delete", chose;
	js("window.__answer = false");
	Alert.alert("Delete?", "Gone for good", [
		{ text: "Cancel", style: "cancel", onPress: (): void => { chose = "cancel"; } },
		{ text: "Delete", style: "destructive", onPress: (): void => { chose = "delete"; } },
	]);
	assert chose === "cancel", chose;
	let ok = false;
	Alert.alert("Saved", "", [{ text: "OK", onPress: (): void => { ok = true; } }]);
	assert ok;
	assert js("JSON.stringify(window.__asked)") === "[\"Delete?\\n\\nGone for good\",\"Delete?\\n\\nGone for good\",\"alert:Saved\"]", js("JSON.stringify(window.__asked)");
}

test "Linking opens a new window, reports the page as the initial URL and rejects settings" {
	mount();
	js("window.__opened = []; window.open = (u, t, f) => { window.__opened.push(u + ' ' + t + ' ' + f); return null; }");
	await Linking.openURL("https://example.com/a");
	assert js("window.__opened.join('|')") === "https://example.com/a _blank noopener", js("window.__opened.join('|')");
	assert await Linking.canOpenURL("mailto:a@b.c");
	assert await Linking.getInitialURL() === js("location.href");
	let message = "";
	try {
		await Linking.openSettings();
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Unable to open the app's settings", message;
}

test "Share goes through navigator.share and reports a cancel as dismissed" {
	mount();
	js("window.__shared = []; navigator.share = (d) => { window.__shared.push(d.title + '|' + d.text + '|' + d.url); return window.__shareCancels ? Promise.reject(new DOMException('cancel', 'AbortError')) : Promise.resolve(); }");
	const shared = await Share.share({ message: "hello", url: "https://neon.dev" }, { dialogTitle: "Send" });
	assert shared.action === Share.sharedAction, shared.action;
	js("window.__shareCancels = true");
	const dismissed = await Share.share({ message: "again" });
	assert dismissed.action === Share.dismissedAction, dismissed.action;
	assert js("window.__shared.join(';')") === "Send|hello|https://neon.dev;|again|", js("window.__shared.join(';')");
}

test "Share rejects where the browser has no navigator.share" {
	mount();
	js("delete navigator.share; Object.defineProperty(navigator, 'share', { configurable: true, value: undefined })");
	let message = "";
	try {
		await Share.share({ message: "hi" });
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Share is not supported in this browser", message;
}

test "Vibration turns RN's pause-first pattern into the web's vibrate-first pattern" {
	mount();
	js("window.__vibrations = []; navigator.vibrate = (p) => { window.__vibrations.push(JSON.stringify(p)); return true; }");
	Vibration.vibrate();
	Vibration.vibrate([100, 200, 300]);
	Vibration.cancel();
	assert js("window.__vibrations.join(';')") === "[0,0,400];[0,100,200,300];[0]", js("window.__vibrations.join(';')");
}

test "Clipboard round-trips text in the page" {
	mount();
	Clipboard.setString("neon clip");
	assert await Clipboard.getString() === "neon clip";
	assert await Clipboard.hasString();
}

test "Keyboard.dismiss blurs the focused input; announcements go to a live region" {
	const handles: TextInputHandle[] = [];
	render(element(<TextInput ref={(h: TextInputHandle): void => { handles.push(h); }} />), domHost(), documentBody());
	handles[0].focus();
	assert js("document.activeElement.tagName") === "INPUT", js("document.activeElement.tagName");
	Keyboard.dismiss();
	assert js("document.activeElement.tagName") === "BODY", js("document.activeElement.tagName");
	AccessibilityInfo.announceForAccessibility("Saved");
	assert js("document.querySelector('[aria-live]').textContent") === "Saved";
	assert !(await AccessibilityInfo.isScreenReaderEnabled());
}
