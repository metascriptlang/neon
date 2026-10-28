import { AsyncStorage } from "../../src/api/asyncStorage";
import { installStorageServices } from "../../src/api/storageServices";
import { createIonStorage } from "../../src/platform/ion/storage";
import { readFile, remove, removeAll, writeFile } from "std/fs";
import { tmpDir } from "std/os";

function scratch(name: string): string {
	const dir = tmpDir() + "/neonIonStorage-" + name;
	removeAll(dir);
	return dir;
}

test "the Ion desktop storage round-trips set, merge, remove, clear and the multi calls through AsyncStorage" {
	const dir = scratch("roundtrip");
	installStorageServices(createIonStorage(dir));
	assert (await AsyncStorage.getItem("note")) === null;
	await AsyncStorage.setItem("note", "hello");
	await AsyncStorage.setItem("empty", "");
	assert (await AsyncStorage.getItem("note")) === "hello";
	assert (await AsyncStorage.getItem("empty")) === "", "an empty string is a value, not a missing key";
	assert (await AsyncStorage.getAllKeys()).join(",") === "note,empty";
	await AsyncStorage.mergeItem("user", "{\"name\":\"Ann\",\"traits\":{\"hair\":\"brown\",\"eyes\":\"blue\"}}");
	await AsyncStorage.mergeItem("user", "{\"age\":31,\"traits\":{\"hair\":\"black\"}}");
	assert (await AsyncStorage.getItem("user")) === "{\"name\":\"Ann\",\"traits\":{\"hair\":\"black\",\"eyes\":\"blue\"},\"age\":31}", "deep merge";
	await AsyncStorage.multiSet([["a", "1"], ["b", "2"]]);
	const read = await AsyncStorage.multiGet(["a", "missing", "b"]);
	assert read[0][1] === "1" && read[1][1] === null && read[2][1] === "2";
	await AsyncStorage.multiRemove(["a", "b"]);
	await AsyncStorage.removeItem("note");
	await AsyncStorage.removeItem("never-set");
	assert (await AsyncStorage.getAllKeys()).join(",") === "empty,user";
	await AsyncStorage.clear();
	assert (await AsyncStorage.getAllKeys()).length === 0;
	removeAll(dir);
}

test "a value, a key with separators and non-ASCII text survive a fresh service over the same directory" {
	const dir = scratch("persist");
	const first = createIonStorage(dir);
	first.storageSet("a/b\u001f\"c", "line1\nline2 é 中");
	first.storageSet("k", "v1");
	first.storageSet("k", "v2");
	const second = createIonStorage(dir);
	assert second.storageGet("a/b\u001f\"c") === "line1\nline2 é 中";
	assert second.storageGet("k") === "v2";
	assert second.storageKeys().join(",") === "a/b\u001f\"c,k";
	second.storageRemove("k");
	assert createIonStorage(dir).storageGet("k") === null;
	const leftover = readFile(dir + "/manifest.json.tmp");
	assert !leftover.ok, "the temp file is renamed away";
	removeAll(dir);
}

test "an IO failure surfaces as an error naming the path and leaves the stored data as it was" {
	const dir = scratch("failure");
	const store = createIonStorage(dir);
	store.storageSet("kept", "1");
	removeAll(dir);
	writeFile(dir, "a file where the directory should be");
	let message = "";
	try {
		store.storageSet("lost", "2");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message.startsWith("AsyncStorage: cannot "), message;
	assert message.includes(dir), message;
	remove(dir);
	const corrupt = scratch("corrupt");
	const bad = createIonStorage(corrupt);
	bad.storageSet("x", "1");
	writeFile(corrupt + "/manifest.json", "{not json");
	message = "";
	try {
		createIonStorage(corrupt).storageGet("x");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message.includes("not a JSON object"), message;
	removeAll(corrupt);
}
