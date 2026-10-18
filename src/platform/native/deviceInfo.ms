import { BatterySnapshot, DeviceInfoServices, DeviceSnapshot, installDeviceInfoServices } from "../../api/deviceInfoServices";
import { FIELD, appCall, ask } from "./appBridge";
import { niDeviceCommand } from "./commands.h";
import { androidLibrary } from "../../../../ion/src/android";

when (ios) {
	@compile("../ios/device.m", "-fobjc-arc");
} else when (android) {
	androidLibrary("../android/device");
}

when (ios || android) {
	function command(name: string, arg: string): string {
		const reply: string = niDeviceCommand(name, arg);
		return reply;
	}
} else {
	function command(name: string, arg: string): string {
		return appCall(name, arg);
	}
}

function decodeDevice(value: string): DeviceSnapshot {
	const fields = value.split(FIELD);
	if (fields.length !== 12) { throw new Error("DeviceInfo: the host sent malformed device info: " + value); }
	return {
		brand: fields[0],
		manufacturer: fields[1],
		model: fields[2],
		deviceId: fields[3],
		systemName: fields[4],
		systemVersion: fields[5],
		applicationName: fields[6],
		bundleId: fields[7],
		version: fields[8],
		buildNumber: fields[9],
		isEmulator: fields[10] === "1",
		isTablet: fields[11] === "1",
	};
}

function deviceInfo(): DeviceSnapshot {
	return decodeDevice(command("device.info", ""));
}

async function battery(): Promise<BatterySnapshot> {
	const fields = (await ask(command, "device.battery", "")).split(FIELD);
	return { level: fields[0] === "" ? -1 : parseFloat(fields[0]), charging: fields.length > 1 && fields[1] === "1" };
}

export const nativeDeviceInfoServices: DeviceInfoServices = { deviceInfo, battery };

installDeviceInfoServices(nativeDeviceInfoServices);
