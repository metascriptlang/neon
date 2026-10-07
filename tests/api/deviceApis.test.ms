import { AsyncStorage, KeyValuePair, StringPair, useAsyncStorage } from "../../src/api/asyncStorage";
import { NetInfo, NetInfoState, publishNetInfo, useNetInfo } from "../../src/api/netInfo";
import { Permissions, PermissionsAndroid } from "../../src/api/permissions";
import { sleepAsync } from "std/core/promise";
import { installAppServices } from "../../src/api/services";
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
