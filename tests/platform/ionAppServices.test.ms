import { installAppServices } from "../../src/api/services";
import { Permissions } from "../../src/api/permissions";
import { Alert } from "../../src/api/alert";
import { AsyncStorage } from "../../src/api/asyncStorage";
import { Linking } from "../../src/api/linking";
import { ionAppServices } from "../../src/platform/ion/appServices";
import "../../../ion/src/index";

test "the microphone permission on an Ion host names the Ion arc it waits for" {
	installAppServices(ionAppServices);
	let message = "";
	try {
		await Permissions.request("microphone");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message.indexOf("Ion arc ion-mic-permission") >= 0, message;
	message = "";
	try {
		await Permissions.check("camera");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Permissions(camera) is not available on an Ion desktop host yet", message;
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
	assert message === "AsyncStorage is not available on an Ion desktop host yet", message;
	message = "";
	try {
		await Linking.openURL("https://example.com");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "Linking.openURL is not available on an Ion desktop host yet", message;
}
