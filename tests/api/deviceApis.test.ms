import { AsyncStorage, KeyValuePair, StringPair, useAsyncStorage } from "../../src/api/asyncStorage";
import { NetInfo, NetInfoState, publishNetInfo, useNetInfo } from "../../src/api/netInfo";
import { Permissions, PermissionsAndroid } from "../../src/api/permissions";
import { sleepAsync } from "std/core/promise";
import { LocationFix, installAppServices } from "../../src/api/services";
import {
	Geolocation, GeolocationError, GeolocationResponse, Location, LocationAccuracy, LocationObject,
} from "../../src/api/geolocation";
import { Haptics, ImpactFeedbackStyle, NotificationFeedbackType } from "../../src/api/haptics";
import { DeviceInfo } from "../../src/api/deviceInfo";
import {
	getCalendars, getCountry, getCurrencies, getLocales, getLocalizeLocales, getNumberFormatSettings, getTemperatureUnit,
	getTimeZone, uses24HourClock, usesMetricSystem,
} from "../../src/api/localization";
import {
	DEFAULT_ACTION_IDENTIFIER, Notification, NotificationBehavior, NotificationRequestInput, NotificationResponse, Notifications,
	publishNotificationEvent,
} from "../../src/api/notifications";
import { FakeServices } from "./fakeServices";

test "AsyncStorage reads null for a missing key and round-trips set, remove and clear" {
	const fake = new FakeServices();
	fake.install();
	assert (await AsyncStorage.getItem("note")) === null;
	await AsyncStorage.setItem("note", "hello");
	await AsyncStorage.setItem("empty", "");
	assert (await AsyncStorage.getItem("note")) === "hello";
	assert (await AsyncStorage.getItem("empty")) === "", "an empty string is a value, not a missing key";
	assert (await AsyncStorage.getAllKeys()).join(",") === "note,empty";
	await AsyncStorage.removeItem("note");
	assert (await AsyncStorage.getItem("note")) === null;
	await AsyncStorage.clear();
	assert (await AsyncStorage.getAllKeys()).length === 0;
}

test "AsyncStorage.multiGet pairs every key with its value or null, multiSet and multiRemove take pairs and keys" {
	const fake = new FakeServices();
	fake.install();
	const writes: StringPair[] = [["a", "1"], ["b", "2"]];
	await AsyncStorage.multiSet(writes);
	const read: KeyValuePair[] = await AsyncStorage.multiGet(["a", "missing", "b"]);
	assert read.length === 3;
	assert read[0][0] === "a" && read[0][1] === "1";
	assert read[1][0] === "missing" && read[1][1] === null;
	assert read[2][1] === "2";
	await AsyncStorage.multiRemove(["a", "b"]);
	assert (await AsyncStorage.getAllKeys()).length === 0;
}

test "AsyncStorage.mergeItem deep-merges JSON objects and stores the value as is when the key is new" {
	const fake = new FakeServices();
	fake.install();
	await AsyncStorage.mergeItem("user", "{\"name\":\"Ann\",\"traits\":{\"hair\":\"brown\",\"eyes\":\"blue\"}}");
	await AsyncStorage.mergeItem("user", "{\"age\":31,\"traits\":{\"hair\":\"black\"}}");
	const user = await AsyncStorage.getItem("user");
	assert user === "{\"name\":\"Ann\",\"traits\":{\"hair\":\"black\",\"eyes\":\"blue\"},\"age\":31}", user ?? "null";
	const merges: StringPair[] = [["user", "{\"age\":32}"], ["other", "[1,2]"]];
	await AsyncStorage.multiMerge(merges);
	assert (await AsyncStorage.getItem("other")) === "[1,2]";
	assert ((await AsyncStorage.getItem("user")) ?? "").endsWith("\"age\":32}");
}

test "AsyncStorage.mergeItem refuses a value or a stored item that is not JSON" {
	const fake = new FakeServices();
	fake.install();
	await AsyncStorage.setItem("plain", "not json");
	let message = "";
	try {
		await AsyncStorage.mergeItem("plain", "{\"a\":1}");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "AsyncStorage.mergeItem: the value of plain is not JSON: not json", message;
	assert (await AsyncStorage.getItem("plain")) === "not json", "a refused merge writes nothing";
}

test "useAsyncStorage binds the item methods to one key" {
	const fake = new FakeServices();
	fake.install();
	const item = useAsyncStorage("draft");
	await item.setItem("{\"a\":1}");
	await item.mergeItem("{\"b\":2}");
	assert (await item.getItem()) === "{\"a\":1,\"b\":2}";
	await item.removeItem();
	assert (await item.getItem()) === null;
}

function describe(state: NetInfoState): string {
	const type: string = state.type;
	const connected = state.isConnected;
	const reachable = state.isInternetReachable;
	const details = state.details;
	return type + " " + (connected === null ? "?" : (connected ? "up" : "down")) + " " +
		(reachable === null ? "?" : (reachable ? "reachable" : "unreachable")) +
		(details === null ? "" : (details.isConnectionExpensive ? " expensive" : " cheap"));
}

test "NetInfo starts the host's watch once, calls a new listener at once and then on every change" {
	const fake = new FakeServices();
	fake.install();
	const seen: string[] = [];
	const unsubscribe = NetInfo.addEventListener((state: NetInfoState): void => { seen.push(describe(state)); });
	const network = useNetInfo();
	assert describe(network()) === "wifi up reachable cheap";
	publishNetInfo({ type: "cellular", isConnected: true, isInternetReachable: null, details: { isConnectionExpensive: true } });
	publishNetInfo({ type: "cellular", isConnected: true, isInternetReachable: null, details: { isConnectionExpensive: true } });
	publishNetInfo({ type: "none", isConnected: false, isInternetReachable: false, details: null });
	unsubscribe();
	publishNetInfo({ type: "wifi", isConnected: true, isInternetReachable: true, details: { isConnectionExpensive: false } });
	assert seen.join(",") === "wifi up reachable cheap,cellular up ? expensive,none down unreachable", seen.join(",");
	assert describe(network()) === "wifi up reachable cheap", "the accessor keeps following";
	fake.network = { type: "ethernet", isConnected: true, isInternetReachable: true, details: { isConnectionExpensive: false } };
	assert describe(await NetInfo.fetch()) === "ethernet up reachable cheap";
	assert fake.joined() === "watchNetInfo;refreshNetInfo", fake.joined();
}

test "Permissions.check and request answer in expo's PermissionResponse shape" {
	const fake = new FakeServices();
	fake.install();
	const before = await Permissions.check("camera");
	assert before.status === "undetermined" && !before.granted && before.canAskAgain && before.expires === "never";
	const after = await Permissions.request("camera");
	assert after.status === "granted" && after.granted && !after.canAskAgain;
	fake.answer = "denied";
	const location = await Permissions.request("location");
	assert location.status === "denied" && !location.granted;
	assert fake.joined() === "requestPermission camera;requestPermission location", fake.joined();
}

test "PermissionsAndroid names RN's permissions and results and maps requestMultiple per permission" {
	const fake = new FakeServices();
	fake.install();
	assert PermissionsAndroid.PERMISSIONS.CAMERA === "android.permission.CAMERA";
	assert PermissionsAndroid.PERMISSIONS.ADD_VOICEMAIL === "com.android.voicemail.permission.ADD_VOICEMAIL";
	assert PermissionsAndroid.RESULTS.NEVER_ASK_AGAIN === "never_ask_again";
	assert !(await PermissionsAndroid.check(PermissionsAndroid.PERMISSIONS.CAMERA));
	assert (await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.CAMERA)) === "granted";
	assert await PermissionsAndroid.check(PermissionsAndroid.PERMISSIONS.CAMERA);
	fake.answer = "never_ask_again";
	const fine = PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION;
	const coarse = PermissionsAndroid.PERMISSIONS.ACCESS_COARSE_LOCATION;
	const results = await PermissionsAndroid.requestMultiple([fine, coarse]);
	assert results.get(fine) === "never_ask_again" && results.size === 2;
}

test "PermissionsAndroid.request shows the rationale first when the platform asks for one" {
	const fake = new FakeServices();
	fake.install();
	fake.rationale = true;
	const result = PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.RECORD_AUDIO, {
		title: "Microphone",
		message: "To record notes",
		buttonNegative: "Not now",
		buttonPositive: "Continue",
	});
	await sleepAsync(20);
	assert fake.alerts.length === 1, "the rationale alert is up";
	assert fake.alerts[0].buttons.length === 2 && fake.alerts[0].buttons[1].text === "Continue";
	assert fake.joined() === "alert Microphone", fake.joined();
	fake.alerts[0].done(1);
	assert (await result) === "granted";
	assert fake.joined() === "alert Microphone;androidRequestPermissions android.permission.RECORD_AUDIO", fake.joined();
}

// Awaited inside an async helper: a test body that awaits a rejected nullable promise segfaults on C
// (compiler card 2026-10-08-test-block-awaiting-a-rejected-nullable-promise-segfaults.md).
async function storageRejection(): Promise<string> {
	try {
		await AsyncStorage.getItem("k");
	} catch (e) {
		return (e as Error).message;
	}
	return "";
}

test "the async device APIs reject when no host installed app services" {
	installAppServices(null);
	const storage = await storageRejection();
	assert storage.startsWith("AsyncStorage.getItem: no host has installed app services"), storage;
	let permission = "";
	try {
		await Permissions.check("camera");
	} catch (e) {
		permission = (e as Error).message;
	}
	assert permission.startsWith("Permissions.check: no host"), permission;
}

function fixAt(latitude: number, longitude: number): LocationFix {
	return {
		code: 0,
		message: "",
		latitude,
		longitude,
		altitude: 12,
		accuracy: 5,
		altitudeAccuracy: NaN,
		heading: NaN,
		speed: 0,
		timestamp: 1000,
	};
}

function failure(code: int32, message: string): LocationFix {
	const fix = fixAt(0, 0);
	return { ...fix, code, message };
}

test "Geolocation asks for location permission, then reads one fix with RN's defaults" {
	const fake = new FakeServices();
	fake.install();
	let read = "";
	Geolocation.getCurrentPosition((position: GeolocationResponse): void => {
		const coords = position.coords;
		read = coords.latitude.toString() + "," + coords.longitude.toString() + " alt " + (coords.altitude ?? -1).toString() +
			" heading " + (coords.heading === null ? "null" : "set") + " at " + position.timestamp.toString();
	});
	await sleepAsync(20);
	when (js) {
		assert fake.joined() === "", "the browser asks through navigator.geolocation itself: " + fake.joined();
	} else {
		assert fake.joined() === "requestPermission location", fake.joined();
	}
	assert fake.currentRequests.length === 1;
	const request = fake.currentRequests[0];
	assert !request.highAccuracy && request.timeout === -1 && request.maximumAge === -1 && request.distanceFilter === 0;
	fake.currentDone[0](fixAt(10.5, 106.25));
	assert read === "10.5,106.25 alt 12 heading null at 1000", read;
}

test "Geolocation reports a denied permission as error code 1 without reading (native; the browser prompts itself)" {
	when (js) { return; }
	const fake = new FakeServices();
	fake.install();
	fake.answer = "denied";
	let code: number = 0;
	Geolocation.getCurrentPosition(
		(position: GeolocationResponse): void => {},
		(error: GeolocationError): void => { code = error.code; },
		{ enableHighAccuracy: true, timeout: 5000 },
	);
	await sleepAsync(20);
	assert code === 1, code.toString();
	assert fake.currentRequests.length === 0;
}

test "watchPosition streams fixes and errors until clearWatch, and skipPermissionRequests skips the ask" {
	const fake = new FakeServices();
	fake.install();
	Geolocation.setRNConfiguration({ skipPermissionRequests: true });
	const seen: string[] = [];
	const id = Geolocation.watchPosition(
		(position: GeolocationResponse): void => { seen.push(position.coords.latitude.toString()); },
		(error: GeolocationError): void => { seen.push("error " + error.code.toString() + " " + error.message); },
		{ distanceFilter: 5 },
	);
	await sleepAsync(20);
	assert fake.watchIds.length === 1 && fake.watchIds[0] === (id as int32);
	assert fake.watchRequests[0].distanceFilter === 5;
	fake.watchUpdates[0](fixAt(1, 2));
	fake.watchUpdates[0](failure(3, "Location request timed out"));
	Geolocation.clearWatch(id);
	fake.watchUpdates[0](fixAt(3, 4));
	assert seen.join(";") === "1;error 3 Location request timed out", seen.join(";");
	assert fake.joined() === "locationWatch " + id.toString() + ";locationClear " + id.toString(), fake.joined();
	Geolocation.setRNConfiguration({ skipPermissionRequests: false });
}

test "Location.getCurrentPositionAsync resolves expo's LocationObject and rejects with the host's message" {
	const fake = new FakeServices();
	fake.install();
	fake.setPermission("location", "granted");
	const pending = Location.getCurrentPositionAsync({ accuracy: LocationAccuracy.High });
	await sleepAsync(20);
	assert fake.currentRequests[0].highAccuracy && fake.currentRequests[0].maximumAge === 0;
	fake.currentDone[0](fixAt(48.85, 2.35));
	const location: LocationObject = await pending;
	assert location.coords.latitude === 48.85 && location.coords.accuracy === 5;
	const failing = locationRejection();
	await sleepAsync(20);
	fake.currentDone[1](failure(2, "No location provider is enabled"));
	assert (await failing) === "No location provider is enabled";
}

async function locationRejection(): Promise<string> {
	try {
		await Location.getCurrentPositionAsync();
	} catch (e) {
		return (e as Error).message;
	}
	return "";
}

test "Haptics names expo's styles and types on the haptic service" {
	const fake = new FakeServices();
	fake.install();
	await Haptics.impactAsync();
	await Haptics.impactAsync(ImpactFeedbackStyle.Heavy);
	await Haptics.notificationAsync(NotificationFeedbackType.Error);
	await Haptics.selectionAsync();
	assert fake.joined() === "haptic impact medium;haptic impact heavy;haptic notification error;haptic selection ", fake.joined();
}

test "DeviceInfo reads react-native-device-info's fields from the host snapshot" {
	const fake = new FakeServices();
	fake.install();
	assert DeviceInfo.getBrand() === "Apple" && DeviceInfo.getModel() === "iPhone" && DeviceInfo.getDeviceId() === "iPhone17,1";
	assert DeviceInfo.getSystemName() === "iOS" && DeviceInfo.getSystemVersion() === "26.0";
	assert DeviceInfo.getBundleId() === "dev.neon.Fake" && DeviceInfo.getApplicationName() === "Neon";
	assert DeviceInfo.getReadableVersion() === "1.2.0.42";
	assert DeviceInfo.getDeviceType() === "Handset" && !DeviceInfo.isTablet();
	assert await DeviceInfo.isEmulator();
	assert (await DeviceInfo.getManufacturer()) === "Apple";
	assert (await DeviceInfo.getBatteryLevel()) === 0.75;
	assert await DeviceInfo.isBatteryCharging();
}

test "getLocales and getCalendars answer expo-localization's shapes, the react-native-localize helpers read the first locale" {
	const fake = new FakeServices();
	fake.install();
	const locales = getLocales();
	assert locales.length === 2;
	assert locales[0].languageTag === "vi-VN" && locales[0].languageCode === "vi" && locales[0].regionCode === "VN";
	assert locales[0].languageScriptCode === null && locales[0].decimalSeparator === ",";
	assert locales[1].textDirection === "rtl" && locales[1].currencyCode === "EGP";
	const calendars = getCalendars();
	assert calendars[0].timeZone === "Asia/Ho_Chi_Minh" && calendars[0].uses24hourClock === true && calendars[0].firstWeekday === 2;
	assert getTimeZone() === "Asia/Ho_Chi_Minh" && uses24HourClock() && usesMetricSystem();
	assert getCountry() === "VN" && getTemperatureUnit() === "celsius";
	assert getCurrencies().join(",") === "VND,EGP";
	assert getNumberFormatSettings().groupingSeparator === ".";
	assert getLocalizeLocales()[1].isRTL && !getLocalizeLocales()[0].isRTL;
}

test "scheduleNotificationAsync flattens expo's request, names it and refuses a short repeat" {
	const fake = new FakeServices();
	fake.install();
	const id = await Notifications.scheduleNotificationAsync({
		content: { title: "Reminder", body: "Water the plants", data: "{\"plant\":3}" },
		trigger: { seconds: 5 },
	});
	assert id.startsWith("neon-"), id;
	const first = fake.notifications[0];
	assert first.identifier === id && first.title === "Reminder" && first.subtitle === "" && first.body === "Water the plants";
	assert first.data === "{\"plant\":3}" && first.seconds === 5 && !first.repeats && first.date === -1 && first.badge === -1;
	const now = await Notifications.scheduleNotificationAsync({ identifier: "fixed", content: { title: "Now" }, trigger: null });
	assert now === "fixed" && fake.notifications[1].seconds === -1;
	const short = notificationRejection({ content: { title: "Again" }, trigger: { seconds: 10, repeats: true } });
	assert (await short) === "Notifications.scheduleNotificationAsync: a repeating trigger needs at least 60 seconds";
	assert (await notificationRejection({ content: { title: "refuse" }, trigger: null })) === "refused by the fake";
	await Notifications.cancelScheduledNotificationAsync(id);
	await Notifications.cancelAllScheduledNotificationsAsync();
	assert fake.joined() === "cancelNotification " + id + ";cancelAllNotifications", fake.joined();
}

async function notificationRejection(request: NotificationRequestInput): Promise<string> {
	try {
		await Notifications.scheduleNotificationAsync(request);
	} catch (e) {
		return (e as Error).message;
	}
	return "";
}

test "a received notification reaches its listeners and the handler decides how it is presented" {
	const fake = new FakeServices();
	fake.install();
	const seen: string[] = [];
	const subscription = Notifications.addNotificationReceivedListener((notification: Notification): void => {
		seen.push(notification.request.identifier + " " + (notification.request.content.title ?? "untitled"));
	});
	const tapped: string[] = [];
	const responses = Notifications.addNotificationResponseReceivedListener((response: NotificationResponse): void => {
		tapped.push(response.notification.request.identifier + " " + response.actionIdentifier);
	});
	Notifications.setNotificationHandler({
		handleNotification: async (notification: Notification): Promise<NotificationBehavior> => {
			return { shouldShowBanner: true, shouldShowList: true, shouldPlaySound: true, shouldSetBadge: false };
		},
	});
	publishNotificationEvent(["received", "n1", "Hello", "", "World", "", "1000"].join("\u001f"));
	await sleepAsync(20);
	publishNotificationEvent(["response", "n1", "Hello", "", "World", "", "1000"].join("\u001f"));
	subscription.remove();
	responses.remove();
	Notifications.setNotificationHandler(null);
	assert seen.join(",") === "n1 Hello", seen.join(",");
	assert tapped.join(",") === "n1 " + DEFAULT_ACTION_IDENTIFIER, tapped.join(",");
	assert fake.joined() === "presentNotifications yes;presentNotification n1 banner sound;presentNotifications no", fake.joined();
	fake.lastResponse = ["response", "n2", "Cold", "", "", "", "5"].join("\u001f");
	const last = await Notifications.getLastNotificationResponseAsync();
	assert last !== null && (last as NotificationResponse).notification.request.identifier === "n2";
}
