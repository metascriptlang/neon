import { AsyncStorage, KeyValuePair, StringPair, useAsyncStorage } from "../../src/api/asyncStorage";
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
