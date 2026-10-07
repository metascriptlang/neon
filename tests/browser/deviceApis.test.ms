import { domHost, documentBody } from "../../src/platform/browser/dom";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View } from "../../src/components/primitives";
import { AsyncStorage, KeyValuePair } from "../../src/api/asyncStorage";
import { NetInfo, NetInfoState, useNetInfo } from "../../src/api/netInfo";
import { Permissions, PermissionsAndroid } from "../../src/api/permissions";
import { Geolocation, GeolocationError, GeolocationResponse } from "../../src/api/geolocation";
import { sleepAsync } from "std/core/promise";

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

test "Permissions map the browser's permission states and ask through the matching web API" {
	mount();
	js("window.__states = { camera: 'prompt', geolocation: 'granted', notifications: 'denied' }; Object.defineProperty(navigator, 'permissions', { configurable: true, value: { query: (d) => Promise.resolve({ state: window.__states[d.name] }) } })");
	const camera = await Permissions.check("camera");
	assert camera.status === "undetermined" && camera.canAskAgain;
	assert (await Permissions.check("location")).granted;
	const notifications = await Permissions.check("notifications");
	assert notifications.status === "denied" && !notifications.canAskAgain;
	js("Object.defineProperty(navigator, 'mediaDevices', { configurable: true, value: { getUserMedia: (c) => { window.__asked = JSON.stringify(c); window.__states.camera = 'granted'; return Promise.resolve({ getTracks: () => [] }); } } })");
	const asked = await Permissions.request("camera");
	assert asked.granted, asked.status as string;
	assert js("window.__asked") === "{\"video\":true}", js("window.__asked");
	assert !(await PermissionsAndroid.check(PermissionsAndroid.PERMISSIONS.CAMERA));
	assert (await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.CAMERA)) === "denied";
}

test "Geolocation reads navigator.geolocation with the options and clears its watch" {
	mount();
	js("window.__geo = []; Object.defineProperty(navigator, 'geolocation', { configurable: true, value: { getCurrentPosition: (ok, fail, o) => { window.__geo.push('get ' + o.enableHighAccuracy + ' ' + o.timeout + ' ' + o.maximumAge); ok({ coords: { latitude: 10.75, longitude: 106.5, altitude: null, accuracy: 20, altitudeAccuracy: null, heading: null, speed: null }, timestamp: 42 }); }, watchPosition: (ok, fail, o) => { window.__watchOk = ok; window.__watchFail = fail; return 7; }, clearWatch: (id) => { window.__geo.push('clear ' + id); } } })");
	let read = "";
	Geolocation.getCurrentPosition(
		(position: GeolocationResponse): void => {
			read = position.coords.latitude.toString() + " " + (position.coords.altitude === null ? "no altitude" : "altitude") +
				" " + position.timestamp.toString();
		},
		null,
		{ enableHighAccuracy: true, timeout: 3000 },
	);
	await sleepAsync(20);
	assert read === "10.75 no altitude 42", read;
	const seen: string[] = [];
	const id = Geolocation.watchPosition(
		(position: GeolocationResponse): void => { seen.push(position.coords.longitude.toString()); },
		(error: GeolocationError): void => { seen.push("error " + error.code.toString()); },
	);
	await sleepAsync(20);
	js("window.__watchOk({ coords: { latitude: 1, longitude: 2, accuracy: 3 }, timestamp: 1 }); window.__watchFail({ code: 3, message: 'Timeout expired' })");
	Geolocation.clearWatch(id);
	assert seen.join(",") === "2,error 3", seen.join(",");
	assert js("window.__geo.join(',')") === "get true 3000 Infinity,clear 7", js("window.__geo.join(',')");
}
