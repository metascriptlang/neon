import { installAppServices } from "../../src/api/services";
import { Permissions } from "../../src/api/permissions";
import { Alert } from "../../src/api/alert";
import { Linking, LinkingUrlEvent } from "../../src/api/linking";
import { AppState, AppStateStatus } from "../../src/api/appState";
import { installLinkingServices } from "../../src/api/linkingServices";
import { ionLinkingServices, linkingServicesOver, ionLinkingMessage } from "../../src/platform/ion/linking";
import { ionAppStateEvent } from "../../src/platform/ion/appState";
import { WindowEventFocused, WindowEventBlurred } from "../../../ion/src/windowManager";
import { ionAppServices } from "../../src/platform/ion/appServices";
import { installPermissionServices } from "../../src/api/permissionServices";
import { ionPermissionServices } from "../../src/platform/ion/permissions";

test "the microphone and camera permissions on an Ion host are the OS's answer, and another permission is refused by name" {
	installPermissionServices(ionPermissionServices);
	const mic = await Permissions.check("microphone");
	assert mic.status === "granted" || mic.status === "denied" || mic.status === "undetermined", mic.status;
	assert mic.granted === (mic.status === "granted"), "granted follows the status";
	const camera = await Permissions.check("camera");
	assert camera.status === "granted" || camera.status === "denied" || camera.status === "undetermined", camera.status;
	assert camera.granted === (camera.status === "granted"), "granted follows the status";
	let message = "";
	try {
		await Permissions.check("location");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Permissions(location) is not available on an Ion desktop host yet", message;
}

test "a service Ion does not back is refused with the name the author called" {
	installAppServices(ionAppServices);
	let message = "";
	try {
		Alert.alert("Saved");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Alert.alert is not available on an Ion desktop host yet", message;
}

test "Linking on an Ion host opens through Ion, answers canOpenURL true as RN macOS does, and has no initial URL before a deeplink" {
	const opened: string[] = [];
	installLinkingServices(linkingServicesOver((url: string): void => { opened.push(url); }));
	await Linking.openURL("https://example.com");
	assert opened.length === 1 && opened[0] === "https://example.com", "openExternal receives the url";
	assert await Linking.canOpenURL("anything://x"), "canOpenURL";
	assert (await Linking.getInitialURL()) === null, "no deeplink yet";
	installLinkingServices(ionLinkingServices);
}

test "an Ion deeplink message fires the url listener and becomes the initial URL" {
	const seen: string[] = [];
	const sub = Linking.addEventListener("url", (event: LinkingUrlEvent): void => { seen.push(event.url); });
	ionLinkingMessage("tray", "ignored");
	assert seen.length === 0, "another message is not a url";
	ionLinkingMessage("deeplink", "app://a");
	ionLinkingMessage("deeplink", "app://b");
	sub.remove();
	assert seen.length === 2 && seen[0] === "app://a" && seen[1] === "app://b", seen.join(",");
	assert (await Linking.getInitialURL()) === "app://a", "the first deeplink is the initial URL";
}

test "Ion window focus and blur publish active and inactive, as RCTAppState does" {
	const seen: string[] = [];
	const sub = AppState.addEventListener("change", (state: AppStateStatus): void => { seen.push(state); });
	ionAppStateEvent("main", WindowEventBlurred);
	ionAppStateEvent("main", WindowEventFocused);
	sub.remove();
	assert AppState.currentState === "active", AppState.currentState;
	assert seen.join(",") === "inactive,active", seen.join(",");
}
