export interface LocationRequest {
	highAccuracy: boolean;
	timeout: number;
	maximumAge: number;
	distanceFilter: number;
	interval: number;
}

// NaN marks an absent altitude, accuracy, heading or speed; `code` is 0 for a fix, else the
// W3C error code (1 permission denied, 2 position unavailable, 3 timeout).
export interface LocationFix {
	code: int32;
	message: string;
	latitude: number;
	longitude: number;
	altitude: number;
	accuracy: number;
	altitudeAccuracy: number;
	heading: number;
	speed: number;
	timestamp: number;
}

export interface LocationServices {
	locationCurrent: (request: LocationRequest, done: (fix: LocationFix) => void) => void;
	locationWatch: (id: int32, request: LocationRequest, update: (fix: LocationFix) => void) => void;
	locationClear: (id: int32) => void;
}

let installed: LocationServices | null = null;

export function installLocationServices(services: LocationServices | null): void {
	installed = services;
}

export function locationServices(api: string): LocationServices {
	const services = installed;
	if (services === null) { throw new Error(`${api} is not available on this host`); }
	return services;
}
