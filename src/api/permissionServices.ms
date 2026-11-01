export interface PermissionReply {
	status: string;
	canAskAgain: boolean;
}

export interface PermissionServices {
	permissionStatus: (name: string) => Promise<PermissionReply>;
	requestPermission: (name: string) => Promise<PermissionReply>;
	androidPermissionGranted: (permission: string) => Promise<boolean>;
	androidShouldShowRationale: (permission: string) => Promise<boolean>;
	androidRequestPermissions: (permissions: string[]) => Promise<PermissionReply[]>;
}

let installed: PermissionServices | null = null;

export function installPermissionServices(services: PermissionServices | null): void {
	installed = services;
}

export function permissionServices(api: string): PermissionServices {
	const services = installed;
	if (services === null) { throw new Error(`${api} is not available on this host`); }
	return services;
}
