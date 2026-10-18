export interface DeviceSnapshot {
	brand: string;
	manufacturer: string;
	model: string;
	deviceId: string;
	systemName: string;
	systemVersion: string;
	applicationName: string;
	bundleId: string;
	version: string;
	buildNumber: string;
	isEmulator: boolean;
	isTablet: boolean;
}

export interface BatterySnapshot {
	level: number;
	charging: boolean;
}

export interface DeviceInfoServices {
	deviceInfo: () => DeviceSnapshot;
	battery: () => Promise<BatterySnapshot>;
}

let installed: DeviceInfoServices | null = null;

export function installDeviceInfoServices(services: DeviceInfoServices | null): void {
	installed = services;
}

export function deviceInfoServices(api: string): DeviceInfoServices {
	const services = installed;
	if (services === null) { throw new Error(`${api} is not available on this host`); }
	return services;
}
