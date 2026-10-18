export interface LinkingServices {
	openURL: (url: string) => Promise<boolean>;
	canOpenURL: (url: string) => Promise<boolean>;
	initialURL: () => Promise<string>;
	openSettings: () => Promise<boolean>;
}

let installed: LinkingServices | null = null;
let listener: (url: string) => void = (url: string): void => {};

export function installLinkingServices(services: LinkingServices | null): void {
	installed = services;
}

export function linkingServices(api: string): LinkingServices {
	const services = installed;
	if (services === null) { throw new Error(`${api} is not available on this host`); }
	return services;
}

export function listenUrls(next: (url: string) => void): void {
	listener = next;
}

export function urlEvent(url: string): void {
	listener(url);
}
