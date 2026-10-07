import { domHost, documentBody } from "../../src/platform/browser/dom";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View } from "../../src/components/primitives";
import { AsyncStorage, KeyValuePair } from "../../src/api/asyncStorage";
import { NetInfo, NetInfoState, useNetInfo } from "../../src/api/netInfo";

extern function js(code: cstring): string from "String((0, eval)(#))";

function mount(): void {
	render(element(<View />), domHost(), documentBody());
}

test "AsyncStorage keeps items in the page's localStorage" {
	mount();
	js("localStorage.clear(); localStorage.setItem('outside', 'x')");
	assert (await AsyncStorage.getItem("outside")) === "x";
	assert (await AsyncStorage.getItem("missing")) === null;
	await AsyncStorage.setItem("note", "");
	assert (await AsyncStorage.getItem("note")) === "", "an empty string is stored";
	await AsyncStorage.setItem("user", "{\"name\":\"Ann\"}");
	await AsyncStorage.mergeItem("user", "{\"age\":3}");
	assert js("localStorage.getItem('user')") === "{\"name\":\"Ann\",\"age\":3}", js("localStorage.getItem('user')");
	const keys = await AsyncStorage.getAllKeys();
	keys.sort();
	assert keys.join(",") === "note,outside,user", keys.join(",");
	const pairs: KeyValuePair[] = await AsyncStorage.multiGet(["outside", "gone"]);
	assert pairs[0][1] === "x" && pairs[1][1] === null;
	await AsyncStorage.removeItem("outside");
	assert js("String(localStorage.getItem('outside'))") === "null";
	await AsyncStorage.clear();
	assert js("localStorage.length") === "0";
}

test "NetInfo follows navigator.onLine and the window's online and offline events" {
	mount();
	js("Object.defineProperty(navigator, 'onLine', { configurable: true, get: () => window.__online !== false })");
	const network = useNetInfo();
	assert network().isConnected === true;
	const seen: string[] = [];
	const unsubscribe = NetInfo.addEventListener((state: NetInfoState): void => {
		const type: string = state.type;
		seen.push(type + ":" + (state.isConnected === true ? "up" : "down"));
	});
	js("window.__online = false; window.dispatchEvent(new Event('offline'))");
	assert network().isConnected === false;
	const offline: string = network().type;
	assert offline === "none", offline;
	js("window.__online = true; window.dispatchEvent(new Event('online'))");
	unsubscribe();
	const fetched = await NetInfo.fetch();
	assert fetched.isInternetReachable === true;
	assert seen.length === 3 && seen[1] === "none:down" && seen[2].endsWith(":up"), seen.join(",");
}
