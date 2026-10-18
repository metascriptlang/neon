export interface ClipboardServices {
	getClipboard: () => Promise<string>;
	setClipboard: (text: string) => void;
}

let installed: ClipboardServices | null = null;

export function installClipboardServices(services: ClipboardServices | null): void {
	installed = services;
}

export function clipboardServices(api: string): ClipboardServices {
	const services = installed;
	if (services === null) { throw new Error(`${api} is not available on this host`); }
	return services;
}
