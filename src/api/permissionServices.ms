// A host refusal travels as `error`, not as a throw inside the service: on C a rejection awaited
// through a function value is lost (compiler card 2026-10-08-await-through-a-function-field-drops-the-rejection-on-c.md).
export interface PermissionReply {
	status: string;
	canAskAgain: boolean;
	error: string;
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
