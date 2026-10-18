export interface VibrationServices {
	vibrate: (pattern: int32[], repeat: boolean) => void;
	cancelVibration: () => void;
}

let installed: VibrationServices | null = null;

export function installVibrationServices(services: VibrationServices | null): void {
	installed = services;
}

export function vibrationServices(api: string): VibrationServices {
	const services = installed;
	if (services === null) { throw new Error(`${api} is not available on this host`); }
	return services;
}
