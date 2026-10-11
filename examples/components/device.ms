import { createSignal } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { View, Text, Pressable, ScrollView } from "../../src/components/primitives";
import { AsyncStorage } from "../../src/api/asyncStorage";
import { NetInfoState, useNetInfo } from "../../src/api/netInfo";
import { Permissions } from "../../src/api/permissions";
import { Geolocation, GeolocationError, GeolocationResponse } from "../../src/api/geolocation";
import { Haptics, ImpactFeedbackStyle } from "../../src/api/haptics";
import { DeviceInfo } from "../../src/api/deviceInfo";
import { getCalendars, getLocales } from "../../src/api/localization";
import {
	Notification, NotificationBehavior, NotificationHandler, NotificationResponse, Notifications,
} from "../../src/api/notifications";

const styles = createStyles({
	screen: { flex: 1 },
	content: { flexDirection: "column", gap: 6, padding: 12 },
	title: { color: "#cdd6f4", fontSize: 20, fontWeight: "bold" },
	status: { color: "#89b4fa", fontSize: 15 },
	buttons: { flexDirection: "row", flexWrap: "wrap", gap: 6 },
	button: { padding: 10, backgroundColor: "#45475a", color: "#cdd6f4", fontSize: 15 },
});

const NOTE = "neon.device.note";
const PROFILE = "neon.device.profile";

// Module level: on JS an object of async arrows makes its enclosing function async (compiler card
// 2026-10-07-js-outer-function-made-async-by-nested-async.md).
const SHOW_IN_FOREGROUND: NotificationHandler = {
	handleNotification: async (notification: Notification): Promise<NotificationBehavior> => {
		return { shouldShowBanner: true, shouldShowList: true, shouldPlaySound: true, shouldSetBadge: false };
	},
};

function rounded(value: number): string {
	return (Math.round(value * 10000) / 10000).toString();
}

function flag(value: boolean | null): string {
	if (value === null) { return "unknown"; }
	return value === true ? "yes" : "no";
}

function network(state: NetInfoState): string {
	const type: string = state.type;
	return "network " + type + " connected " + flag(state.isConnected) + " reachable " + flag(state.isInternetReachable);
}

export function DeviceDemo(): NeonNode {
	const [stored, setStored] = createSignal("loading");
	const [merged, setMerged] = createSignal("none");
	const [permission, setPermission] = createSignal("unknown");
	const [position, setPosition] = createSignal("none");
	const [watched, setWatched] = createSignal<int32>(0);
	const [haptics, setHaptics] = createSignal<int32>(0);
	const [battery, setBattery] = createSignal("unknown");
	const [notifications, setNotifications] = createSignal("unknown");
	const [notified, setNotified] = createSignal("nothing");
	const net = useNetInfo();
	let watchId: number = -1;
	Notifications.setNotificationHandler(SHOW_IN_FOREGROUND);
	const received = Notifications.addNotificationReceivedListener((notification: Notification): void => {
		setNotified("received " + (notification.request.content.title ?? ""));
	});
	const responded = Notifications.addNotificationResponseReceivedListener((response: NotificationResponse): void => {
		setNotified("response " + (response.notification.request.content.title ?? ""));
	});
	onCleanup((): void => {
		if (watchId >= 0) { Geolocation.clearWatch(watchId); }
		received.remove();
		responded.remove();
		Notifications.setNotificationHandler(null);
	});

	const load = async (): Promise<void> => {
		setStored((await AsyncStorage.getItem(NOTE)) ?? "none");
		setMerged((await AsyncStorage.getItem(PROFILE)) ?? "none");
		setPermission((await Permissions.check("location")).status as string);
		setNotifications((await Notifications.getPermissionsAsync()).status as string);
		const last = await Notifications.getLastNotificationResponseAsync();
		if (last !== null) { setNotified("launched by " + (last.notification.request.content.title ?? "")); }
	};
	const saveNote = async (): Promise<void> => {
		const current = (await AsyncStorage.getItem(NOTE)) ?? "note-0";
		const count = parseInt(current.substring(5, current.length)) + 1;
		await AsyncStorage.setItem(NOTE, "note-" + count.toString());
		setStored((await AsyncStorage.getItem(NOTE)) ?? "none");
	};
	const mergeNote = async (): Promise<void> => {
		await AsyncStorage.mergeItem(PROFILE, "{\"name\":\"neon\",\"tags\":{\"a\":1}}");
		await AsyncStorage.mergeItem(PROFILE, "{\"tags\":{\"b\":2}}");
		setMerged((await AsyncStorage.getItem(PROFILE)) ?? "none");
	};
	const clearNotes = async (): Promise<void> => {
		await AsyncStorage.multiRemove([NOTE, PROFILE]);
		setStored("none");
		setMerged("none");
	};
	const requestLocation = async (): Promise<void> => {
		const answer = await Permissions.request("location");
		setPermission(answer.status as string);
	};
	const allowNotifications = async (): Promise<void> => {
		setNotifications((await Notifications.requestPermissionsAsync()).status as string);
	};
	const notify = async (title: string, seconds: number): Promise<void> => {
		const id = await Notifications.scheduleNotificationAsync({
			content: { title, body: "From the Neon device demo", sound: true },
			trigger: { seconds },
		});
		setNotified("scheduled " + id.substring(0, 5));
	};
	const readBattery = async (): Promise<void> => {
		const level = await DeviceInfo.getBatteryLevel();
		setBattery(level < 0 ? "unknown" : rounded(level));
	};
	load();

	// Read before the JSX: an enum member inside a JSX handler loses its binding (compiler card
	// 2026-10-03-checked-enum-macro-roundtrip-loses-binding.md).
	const heavy = ImpactFeedbackStyle.Heavy;
	const locale = getLocales()[0];
	const calendar = getCalendars()[0];

	return <ScrollView style={styles.screen}>
		<View style={styles.content}>
			<Text style={styles.title}>Neon Device</Text>
			<Text style={styles.status}>{"stored " + stored()}</Text>
			<Text style={styles.status}>{"merged " + merged()}</Text>
			<Text style={styles.status}>{network(net())}</Text>
			<Text style={styles.status}>{"permission " + permission()}</Text>
			<Text style={styles.status}>{"position " + position()}</Text>
			<Text style={styles.status}>{"watched " + watched().toString()}</Text>
			<Text style={styles.status}>{"haptics " + haptics().toString()}</Text>
			<Text style={styles.status}>{"device " + DeviceInfo.getModel() + " " + DeviceInfo.getSystemName() + " " + DeviceInfo.getSystemVersion() +
				" emulator " + (DeviceInfo.isEmulatorSync() ? "yes" : "no")}</Text>
			<Text style={styles.status}>{"app " + DeviceInfo.getBundleId() + " " + DeviceInfo.getVersion() + " (" + DeviceInfo.getBuildNumber() + ")"}</Text>
			<Text style={styles.status}>{"battery " + battery()}</Text>
			<Text style={styles.status}>{"notifications " + notifications()}</Text>
			<Text style={styles.status}>{"notified " + notified()}</Text>
			<Text style={styles.status}>{"locale " + locale.languageTag + " tz " + (calendar.timeZone ?? "none") + " 24h " +
				flag(calendar.uses24hourClock) + " rtl " + (locale.textDirection === "rtl" ? "yes" : "no")}</Text>
			<View style={styles.buttons}>
				<Pressable style={styles.button} onPress={() => { saveNote(); }}>save note</Pressable>
				<Pressable style={styles.button} onPress={() => { mergeNote(); }}>merge note</Pressable>
				<Pressable style={styles.button} onPress={() => { clearNotes(); }}>clear notes</Pressable>
				<Pressable style={styles.button} onPress={() => { requestLocation(); }}>request location</Pressable>
				<Pressable style={styles.button} onPress={() => {
					setPosition("locating");
					Geolocation.getCurrentPosition(
						(fix: GeolocationResponse): void => {
							setPosition(rounded(fix.coords.latitude) + "," + rounded(fix.coords.longitude));
						},
						(error: GeolocationError): void => { setPosition("error " + error.code.toString() + " " + error.message); },
						{ enableHighAccuracy: false, timeout: 30000, maximumAge: 0 },
					);
				}}>locate</Pressable>
				<Pressable style={styles.button} onPress={() => {
					if (watchId >= 0) { return; }
					watchId = Geolocation.watchPosition(
						(fix: GeolocationResponse): void => { setWatched(watched() + 1); },
						(error: GeolocationError): void => { setPosition("watch error " + error.code.toString()); },
						{ distanceFilter: 0 },
					);
				}}>watch location</Pressable>
				<Pressable style={styles.button} onPress={() => {
					Haptics.impactAsync(heavy);
					setHaptics(haptics() + 1);
				}}>haptic</Pressable>
				<Pressable style={styles.button} onPress={() => { readBattery(); }}>battery</Pressable>
				<Pressable style={styles.button} onPress={() => { allowNotifications(); }}>allow notifications</Pressable>
				<Pressable style={styles.button} onPress={() => { notify("Neon reminder", 2); }}>notify</Pressable>
				<Pressable style={styles.button} onPress={() => { notify("Neon later", 15); }}>notify later</Pressable>
			</View>
		</View>
	</ScrollView>;
}
