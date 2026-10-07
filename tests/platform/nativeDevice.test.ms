import { runApp } from "../../src/platform/native/host";
import { View } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { AsyncStorage } from "../../src/api/asyncStorage";
import { NetInfo, NetInfoState, useNetInfo } from "../../src/api/netInfo";
import { Permissions, PermissionResponse, PermissionsAndroid } from "../../src/api/permissions";
import { sleepAsync } from "std/core/promise";
import { Geolocation, GeolocationError, GeolocationResponse } from "../../src/api/geolocation";
import { Haptics, ImpactFeedbackStyle } from "../../src/api/haptics";
import { DeviceInfo } from "../../src/api/deviceInfo";
import { getCalendars, getLocales } from "../../src/api/localization";
import { nmAppReply, nmAppLog, nmAppLogClear, nmAppEvent, nmTeardown } from "./nativeBridgeMock.h";

const FIELD = "\u001f";
const RECORD = "\u001e";
const REPLY: int32 = 9;
const NETINFO: int32 = 10;
const LOCATION: int32 = 11;

function mount(): void {
	nmAppReply("platform", "17.5");
	nmAppReply("pixelRatio", "3");
	nmAppReply("fontScale", "1");
	nmAppReply("screen", "393" + FIELD + "852");
	nmAppReply("appState", "active");
	runApp((): NeonNode => <View />);
	nmAppLogClear();
}

test "AsyncStorage goes through the storage commands; a stored value is marked so an empty one is not missing" {
	mount();
	nmAppReply("storage.get", "=");
	assert (await AsyncStorage.getItem("empty")) === "";
	nmAppReply("storage.get", "");
	assert (await AsyncStorage.getItem("missing")) === null;
	nmAppReply("storage.get", "={\"a\":1}");
	await AsyncStorage.mergeItem("user", "{\"b\":2}");
	await AsyncStorage.removeItem("old");
	nmAppReply("storage.keys", "a" + FIELD + "b");
	assert (await AsyncStorage.getAllKeys()).join(",") === "a,b";
	nmAppReply("storage.keys", "");
	assert (await AsyncStorage.getAllKeys()).length === 0;
	await AsyncStorage.clear();
	const expected = [
		"storage.get(empty)",
		"storage.get(missing)",
		"storage.get(user)",
		"storage.set(user" + FIELD + "{\"a\":1,\"b\":2})",
		"storage.remove(old)",
		"storage.keys()",
		"storage.keys()",
		"storage.clear()",
	];
	const log: string = nmAppLog();
	assert log === expected.join(";"), log;
	nmTeardown();
}

function network(state: NetInfoState): string {
	const type: string = state.type;
	const details = state.details;
	return type + "/" + (state.isConnected === null ? "?" : (state.isConnected === true ? "1" : "0")) + "/" +
		(state.isInternetReachable === null ? "?" : (state.isInternetReachable === true ? "1" : "0")) + "/" +
		(details === null ? "-" : (details.isConnectionExpensive ? "metered" : "free"));
}

test "NetInfo decodes the host's state on watch, fetch and the netinfo event" {
	mount();
	nmAppReply("netinfo.watch", "unknown" + FIELD + "" + FIELD + "" + FIELD + "0");
	const state = useNetInfo();
	assert network(state()) === "unknown/?/?/-", network(state());
	nmAppEvent(NETINFO, "wifi" + FIELD + "1" + FIELD + "1" + FIELD + "0");
	assert network(state()) === "wifi/1/1/free", network(state());
	nmAppEvent(NETINFO, "cellular" + FIELD + "1" + FIELD + "0" + FIELD + "1");
	assert network(state()) === "cellular/1/0/metered", network(state());
	nmAppReply("netinfo.fetch", "none" + FIELD + "0" + FIELD + "0" + FIELD + "0");
	assert network(await NetInfo.fetch()) === "none/0/0/-";
	const log: string = nmAppLog();
	assert log === "netinfo.watch();netinfo.fetch()", log;
	nmTeardown();
}

function requestId(log: string, command: string): string {
	const at = log.lastIndexOf(command + "(");
	const start = at + command.length + 1;
	return log.substring(start, log.indexOf(FIELD, start));
}

test "Permissions answer at once when the host replies, else on the reply event carrying the request id" {
	mount();
	nmAppReply("permission.check", "granted" + FIELD + "0");
	const camera = await Permissions.check("camera");
	assert camera.granted && camera.status === "granted" && !camera.canAskAgain;
	nmAppReply("permission.request", "");
	const pending = Permissions.request("location");
	await sleepAsync(5);
	const asked: string = nmAppLog();
	const id = requestId(asked, "permission.request");
	assert asked.endsWith("permission.request(" + id + FIELD + "location)"), asked;
	nmAppEvent(REPLY, "999" + FIELD + "granted" + FIELD + "0");
	nmAppEvent(REPLY, id + FIELD + "denied" + FIELD + "1");
	const location: PermissionResponse = await pending;
	assert location.status === "denied" && location.canAskAgain, location.status as string;
	nmTeardown();
}

test "a host refusal reply becomes a thrown error naming what the app must declare" {
	mount();
	nmAppReply("permission.request", "!Permissions.request(camera): add NSCameraUsageDescription to the app's Info.plist");
	let message = "";
	try {
		await Permissions.request("camera");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Permissions.request(camera): add NSCameraUsageDescription to the app's Info.plist", message;
	nmTeardown();
}

test "PermissionsAndroid sends raw permission names and reads one result per permission" {
	mount();
	nmAppReply("permissionsAndroid.check", "1");
	assert await PermissionsAndroid.check(PermissionsAndroid.PERMISSIONS.CAMERA);
	nmAppReply("permissionsAndroid.request", "granted" + FIELD + "never_ask_again");
	const fine = PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION;
	const coarse = PermissionsAndroid.PERMISSIONS.ACCESS_COARSE_LOCATION;
	const results = await PermissionsAndroid.requestMultiple([fine, coarse]);
	assert results.get(fine) === "granted" && results.get(coarse) === "never_ask_again";
	const log: string = nmAppLog();
	const id = requestId(log, "permissionsAndroid.request");
	assert log === "permissionsAndroid.check(android.permission.CAMERA);permissionsAndroid.request(" + id + FIELD + fine + "," + coarse + ")", log;
	nmTeardown();
}

test "Geolocation encodes its options, decodes fixes with absent fields as null and routes watch events by id" {
	mount();
	nmAppReply("permission.request", "granted" + FIELD + "0");
	nmAppReply("location.current", "ok" + FIELD + "10.5" + FIELD + "106.25" + FIELD + "" + FIELD + "35" + FIELD + "" +
		FIELD + "90" + FIELD + "1.5" + FIELD + "1700000000000");
	let read = "";
	Geolocation.getCurrentPosition(
		(position: GeolocationResponse): void => {
			const c = position.coords;
			read = c.latitude.toString() + "," + c.longitude.toString() + " alt " + (c.altitude === null ? "null" : "set") +
				" acc " + c.accuracy.toString() + " heading " + (c.heading ?? -1).toString() + " speed " + (c.speed ?? -1).toString();
		},
		null,
		{ enableHighAccuracy: true, timeout: 5000, maximumAge: 1000 },
	);
	await sleepAsync(20);
	assert read === "10.5,106.25 alt null acc 35 heading 90 speed 1.5", read;
	const current: string = nmAppLog();
	const id = requestId(current, "location.current");
	assert current.endsWith("location.current(" + id + FIELD + "1" + FIELD + "5000" + FIELD + "1000" + FIELD + "0" + FIELD + "10000)"), current;
	nmAppLogClear();
	const seen: string[] = [];
	const watch = Geolocation.watchPosition(
		(position: GeolocationResponse): void => { seen.push(position.coords.latitude.toString()); },
		(error: GeolocationError): void => { seen.push(error.code.toString() + " " + error.message); },
	);
	await sleepAsync(20);
	const fix = "ok" + FIELD + "1" + FIELD + "2" + FIELD + "3" + FIELD + "4" + FIELD + "5" + FIELD + "6" + FIELD + "7" + FIELD + "8";
	nmAppEvent(LOCATION, watch.toString() + FIELD + fix);
	nmAppEvent(LOCATION, "999" + FIELD + fix);
	nmAppEvent(LOCATION, watch.toString() + FIELD + "error" + FIELD + "2" + FIELD + "No location provider is enabled");
	Geolocation.clearWatch(watch);
	nmAppEvent(LOCATION, watch.toString() + FIELD + fix);
	assert seen.join(";") === "1;2 No location provider is enabled", seen.join(";");
	const log: string = nmAppLog();
	const permission = requestId(log, "permission.request");
	assert log === "permission.request(" + permission + FIELD + "location);location.watch(" + watch.toString() + FIELD + "0" + FIELD +
		"-1" + FIELD + "-1" + FIELD + "100" + FIELD + "10000);location.clear(" + watch.toString() + ")", log;
	nmTeardown();
}

test "Haptics, DeviceInfo and the locale readout go through their commands and decode the host's fields" {
	mount();
	await Haptics.impactAsync(ImpactFeedbackStyle.Rigid);
	await Haptics.selectionAsync();
	nmAppReply("device.info", ["Google", "Google", "Pixel 9", "tokay", "Android", "16", "Neon Device", "dev.neon.NeonDevice",
		"1.0", "1", "0", "0"].join(FIELD));
	assert DeviceInfo.getModel() === "Pixel 9" && DeviceInfo.getDeviceId() === "tokay" && DeviceInfo.getSystemVersion() === "16";
	assert DeviceInfo.getBundleId() === "dev.neon.NeonDevice" && !DeviceInfo.isEmulatorSync();
	nmAppReply("device.battery", "0.42" + FIELD + "1");
	assert (await DeviceInfo.getBatteryLevel()) === 0.42;
	nmAppReply("device.battery", "" + FIELD + "0");
	assert (await DeviceInfo.getBatteryLevel()) === -1, "an unknown level is -1, as react-native-device-info";
	nmAppReply("locale.info", ["gregory", "Europe/Paris", "1", "2"].join(FIELD) + RECORD +
		["fr-FR", "fr", "", "FR", "ltr", ",", " ", "metric", "EUR", "€", "celsius"].join(FIELD) + RECORD +
		["he-IL", "he", "", "IL", "rtl", ".", ",", "metric", "ILS", "₪", "celsius"].join(FIELD));
	const locales = getLocales();
	assert locales.length === 2 && locales[0].currencySymbol === "€" && locales[1].textDirection === "rtl";
	assert getCalendars()[0].timeZone === "Europe/Paris" && getCalendars()[0].firstWeekday === 2;
	const log: string = nmAppLog();
	assert log.startsWith("haptics.impact(rigid);haptics.selection();device.info()"), log;
	nmTeardown();
}
