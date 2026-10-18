import { installAppServices } from "../../src/api/services";
import { Permissions } from "../../src/api/permissions";
import { Alert } from "../../src/api/alert";
import { AsyncStorage } from "../../src/api/asyncStorage";
import { Linking } from "../../src/api/linking";
import { ionAppServices } from "../../src/platform/ion/appServices";

test "the microphone and camera permissions on an Ion host are the OS's answer, and another permission is refused by name" {
	installAppServices(ionAppServices);
	const mic = await Permissions.check("microphone");
	assert mic.status === "granted" || mic.status === "denied" || mic.status === "undetermined", mic.status;
	assert mic.granted === (mic.status === "granted"), "granted follows the status";
	const camera = await Permissions.check("camera");
	assert camera.status === "granted" || camera.status === "denied" || camera.status === "undetermined", camera.status;
	assert camera.granted === (camera.status === "granted"), "granted follows the status";
	let message = "";
	try {
		await Permissions.check("location");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Permissions(location) is not available on an Ion desktop host yet", message;
}

test "a service Ion does not back is refused with the name the author called" {
	installAppServices(ionAppServices);
	let message = "";
	try {
		Alert.alert("Saved");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Alert.alert is not available on an Ion desktop host yet", message;
	message = "";
	try {
		await AsyncStorage.setItem("k", "v");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "AsyncStorage.setItem is not available on this host", message;
	message = "";
	try {
		await Linking.openURL("https://example.com");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Linking.openURL is not available on an Ion desktop host yet", message;
}
