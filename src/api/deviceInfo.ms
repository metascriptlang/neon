import { BatterySnapshot, DeviceSnapshot, appServices } from "./services";

export type DeviceType = "Handset" | "Tablet" | "Tv" | "Desktop" | "GamingConsole" | "Headset" | "unknown";

function snapshot(api: string): DeviceSnapshot {
	return appServices(api).deviceInfo();
}

export class DeviceInfo {
	static getBrand(): string {
		return snapshot("DeviceInfo.getBrand").brand;
	}

	static getModel(): string {
		return snapshot("DeviceInfo.getModel").model;
	}

	static getDeviceId(): string {
		return snapshot("DeviceInfo.getDeviceId").deviceId;
	}

	static getSystemName(): string {
		return snapshot("DeviceInfo.getSystemName").systemName;
	}

	static getSystemVersion(): string {
		return snapshot("DeviceInfo.getSystemVersion").systemVersion;
	}

	static getApplicationName(): string {
		return snapshot("DeviceInfo.getApplicationName").applicationName;
	}

	static getBundleId(): string {
		return snapshot("DeviceInfo.getBundleId").bundleId;
	}

	static getVersion(): string {
		return snapshot("DeviceInfo.getVersion").version;
	}

	static getBuildNumber(): string {
		return snapshot("DeviceInfo.getBuildNumber").buildNumber;
	}

	static getReadableVersion(): string {
		const device = snapshot("DeviceInfo.getReadableVersion");
		return device.version + "." + device.buildNumber;
	}

	static isTablet(): boolean {
		return snapshot("DeviceInfo.isTablet").isTablet;
	}

	static getDeviceType(): DeviceType {
		const device = snapshot("DeviceInfo.getDeviceType");
		if (device.systemName === "") { return "Desktop"; }
		return device.isTablet ? "Tablet" : "Handset";
	}

	static getManufacturerSync(): string {
		return snapshot("DeviceInfo.getManufacturer").manufacturer;
	}

	static async getManufacturer(): Promise<string> {
		const manufacturer = DeviceInfo.getManufacturerSync();
		return manufacturer;
	}

	static isEmulatorSync(): boolean {
		return snapshot("DeviceInfo.isEmulator").isEmulator;
	}

	static async isEmulator(): Promise<boolean> {
		const emulator = DeviceInfo.isEmulatorSync();
		return emulator;
	}

	static async getBatteryLevel(): Promise<number> {
		const battery: BatterySnapshot = await appServices("DeviceInfo.getBatteryLevel").battery();
		return battery.level;
	}

	static async isBatteryCharging(): Promise<boolean> {
		const battery: BatterySnapshot = await appServices("DeviceInfo.isBatteryCharging").battery();
		return battery.charging;
	}
}
