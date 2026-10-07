import { runApp } from "../../src/platform/native/host";
import { View } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { AsyncStorage } from "../../src/api/asyncStorage";
import { NetInfo, NetInfoState, useNetInfo } from "../../src/api/netInfo";
import { nmAppReply, nmAppLog, nmAppLogClear, nmAppEvent, nmTeardown } from "./nativeBridgeMock.h";

const FIELD = "\u001f";
const RECORD = "\u001e";
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
