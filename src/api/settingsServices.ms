export interface SettingsServices {
	settingsGet: (key: string) => string | null;
	settingsSet: (values: string) => void;
	watchSettings: () => void;
}

let installed: SettingsServices | null = null;
let listener: () => void = (): void => {};

export function installSettingsServices(services: SettingsServices | null): void {
	installed = services;
}

export function installedSettingsServices(): SettingsServices | null {
	return installed;
}

export function listenSettings(next: () => void): void {
	listener = next;
}

export function settingsEvent(): void {
	listener();
}
