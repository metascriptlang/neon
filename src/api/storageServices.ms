export interface StorageServices {
	storageGet: (key: string) => string | null;
	storageSet: (key: string, value: string) => void;
	storageRemove: (key: string) => void;
	storageClear: () => void;
	storageKeys: () => string[];
}

let installed: StorageServices | null = null;

export function installStorageServices(services: StorageServices | null): void {
	installed = services;
}

export function storageServices(api: string): StorageServices {
	const services = installed;
	if (services === null) { throw new Error(`${api} is not available on this host`); }
	return services;
}
