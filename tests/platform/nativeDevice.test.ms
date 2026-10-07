import { runApp } from "../../src/platform/native/host";
import { View } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { AsyncStorage } from "../../src/api/asyncStorage";
import { nmAppReply, nmAppLog, nmAppLogClear, nmAppEvent, nmTeardown } from "./nativeBridgeMock.h";

const FIELD = "\u001f";
const RECORD = "\u001e";

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
