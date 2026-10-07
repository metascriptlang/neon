import { runApp } from "../../src/platform/native/host";
import { View } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { AsyncStorage } from "../../src/api/asyncStorage";
import { NetInfo, NetInfoState, useNetInfo } from "../../src/api/netInfo";
import { Permissions, PermissionResponse, PermissionsAndroid } from "../../src/api/permissions";
import { sleepAsync } from "std/core/promise";
import { nmAppReply, nmAppLog, nmAppLogClear, nmAppEvent, nmTeardown } from "./nativeBridgeMock.h";

const FIELD = "\u001f";
const RECORD = "\u001e";
const REPLY: int32 = 9;
const NETINFO: int32 = 10;

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
