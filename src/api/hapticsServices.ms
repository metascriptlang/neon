export interface HapticsServices {
	haptic: (kind: string, style: string) => void;
}

let installed: HapticsServices | null = null;

export function installHapticsServices(services: HapticsServices | null): void {
	installed = services;
}

export function hapticsServices(api: string): HapticsServices {
	const services = installed;
	if (services === null) { throw new Error(`${api} is not available on this host`); }
	return services;
}
