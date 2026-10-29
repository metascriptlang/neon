import { LocationFix, LocationRequest, locationServices } from "./locationServices";
import { INT32_MAX, checkedInt32, finiteOrNull } from "./hostCodec";
import { Permissions, PermissionResponse } from "./permissions";

when (js && !server) {
	import "../platform/browser/geolocation";
} else when (ios || android) {
	import "../platform/native/geolocation";
}

export interface GeolocationCoordinates {
	latitude: number;
	longitude: number;
	altitude: number | null;
	accuracy: number;
	altitudeAccuracy: number | null;
	heading: number | null;
	speed: number | null;
}

export interface GeolocationResponse {
	coords: GeolocationCoordinates;
	timestamp: number;
}

export interface GeolocationError {
	code: number;
	message: string;
	PERMISSION_DENIED: number;
	POSITION_UNAVAILABLE: number;
	TIMEOUT: number;
}

export interface GeolocationOptions {
	timeout?: number | null;
	maximumAge?: number | null;
	enableHighAccuracy?: boolean | null;
	distanceFilter?: number | null;
	interval?: number | null;
	fastestInterval?: number | null;
	useSignificantChanges?: boolean | null;
}

export interface GeolocationConfiguration {
	skipPermissionRequests: boolean;
	authorizationLevel?: string | null;
	enableBackgroundLocationUpdates?: boolean | null;
	locationProvider?: string | null;
}

export type GeolocationSuccess = (position: GeolocationResponse) => void;
export type GeolocationFailure = (error: GeolocationError) => void;

const PERMISSION_DENIED = 1;
const POSITION_UNAVAILABLE = 2;
const TIMEOUT = 3;
const FOREVER = -1;

let skipPermissionRequests = false;
let nextWatch: int32 = 1;
const live = new Set<int32>();
const started = new Set<int32>();

function present(value: number): number | null {
	return Number.isNaN(value) ? null : value;
}

export function geolocationError(code: number, message: string): GeolocationError {
	return { code, message, PERMISSION_DENIED, POSITION_UNAVAILABLE, TIMEOUT };
}

export function positionOf(fix: LocationFix): GeolocationResponse {
	return {
		coords: {
			latitude: fix.latitude,
			longitude: fix.longitude,
			altitude: present(fix.altitude),
			accuracy: Number.isNaN(fix.accuracy) ? 0 : fix.accuracy,
			altitudeAccuracy: present(fix.altitudeAccuracy),
			heading: present(fix.heading),
			speed: present(fix.speed),
		},
		timestamp: fix.timestamp,
	};
}

function finiteOr(value: number | null, fallback: number): number {
	return finiteOrNull(value) ?? fallback;
}

export function locationRequest(options: GeolocationOptions, watching: boolean): LocationRequest {
	return {
		highAccuracy: options.enableHighAccuracy === true,
		timeout: finiteOr(options.timeout ?? null, FOREVER),
		maximumAge: finiteOr(options.maximumAge ?? null, FOREVER),
		distanceFilter: finiteOr(options.distanceFilter ?? null, watching ? 100 : 0),
		interval: finiteOr(options.interval ?? null, 10000),
	};
}

function report(fix: LocationFix, success: GeolocationSuccess, error: GeolocationFailure | null): void {
	if (fix.code === 0) {
		success(positionOf(fix));
		return;
	}
	if (error !== null) { error(geolocationError(fix.code, fix.message)); }
}

function deniedFix(): LocationFix {
	return {
		code: PERMISSION_DENIED as int32,
		message: "Location permission was not granted.",
		latitude: 0,
		longitude: 0,
		altitude: NaN,
		accuracy: NaN,
		altitudeAccuracy: NaN,
		heading: NaN,
		speed: NaN,
		timestamp: 0,
	};
}

when (js) {
	async function authorized(): Promise<boolean> {
		return true;
	}
} else {
	async function authorized(): Promise<boolean> {
		if (skipPermissionRequests) { return true; }
		const answer = await Permissions.request("location");
		return answer.granted;
	}
}

async function readCurrent(request: LocationRequest, success: GeolocationSuccess, error: GeolocationFailure | null): Promise<void> {
	if (!(await authorized())) {
		report(deniedFix(), success, error);
		return;
	}
	locationServices("Geolocation.getCurrentPosition").locationCurrent(request, (fix: LocationFix): void => {
		report(fix, success, error);
	});
}

async function startWatch(id: int32, request: LocationRequest, success: GeolocationSuccess, error: GeolocationFailure | null): Promise<void> {
	const allowed = await authorized();
	if (!live.has(id)) { return; }
	if (!allowed) {
		report(deniedFix(), success, error);
		return;
	}
	started.add(id);
	locationServices("Geolocation.watchPosition").locationWatch(id, request, (fix: LocationFix): void => {
		if (live.has(id)) { report(fix, success, error); }
	});
}

export class Geolocation {
	static setRNConfiguration(config: GeolocationConfiguration): void {
		skipPermissionRequests = config.skipPermissionRequests;
	}

	static requestAuthorization(success: (() => void) | null = null, error: GeolocationFailure | null = null): void {
		Geolocation.authorize(success, error);
	}

	private static async authorize(success: (() => void) | null, error: GeolocationFailure | null): Promise<void> {
		const answer: PermissionResponse = await Permissions.request("location");
		if (answer.granted) {
			if (success !== null) { success(); }
			return;
		}
		if (error !== null) { error(geolocationError(PERMISSION_DENIED, "Location permission was not granted.")); }
	}

	static getCurrentPosition(
		success: GeolocationSuccess,
		error: GeolocationFailure | null = null,
		options: GeolocationOptions = {},
	): void {
		readCurrent(locationRequest(options, false), success, error);
	}

	static watchPosition(
		success: GeolocationSuccess,
		error: GeolocationFailure | null = null,
		options: GeolocationOptions = {},
	): number {
		const id = nextWatch;
		nextWatch += 1;
		live.add(id);
		startWatch(id, locationRequest(options, true), success, error);
		return id as number;
	}

	static clearWatch(watchId: number): void {
		const id = checkedInt32("Geolocation.clearWatch", "watchId", watchId, 0, INT32_MAX);
		if (!live.delete(id)) { return; }
		if (!started.delete(id)) { return; }
		locationServices("Geolocation.clearWatch").locationClear(id);
	}

	static stopObserving(): void {
		for (const id of [...started]) { Geolocation.clearWatch(id as number); }
	}
}

export enum LocationAccuracy {
	Lowest = 1,
	Low = 2,
	Balanced = 3,
	High = 4,
	Highest = 5,
	BestForNavigation = 6,
}

export interface LocationOptions {
	accuracy?: LocationAccuracy | null;
	timeInterval?: number | null;
	distanceInterval?: number | null;
	maximumAge?: number | null;
	timeout?: number | null;
}

export interface LocationObjectCoords {
	latitude: number;
	longitude: number;
	altitude: number | null;
	accuracy: number | null;
	altitudeAccuracy: number | null;
	heading: number | null;
	speed: number | null;
}

export interface LocationObject {
	coords: LocationObjectCoords;
	timestamp: number;
}

export interface LocationSubscription {
	remove: () => void;
}

function locationObject(fix: LocationFix): LocationObject {
	return {
		coords: {
			latitude: fix.latitude,
			longitude: fix.longitude,
			altitude: present(fix.altitude),
			accuracy: present(fix.accuracy),
			altitudeAccuracy: present(fix.altitudeAccuracy),
			heading: present(fix.heading),
			speed: present(fix.speed),
		},
		timestamp: fix.timestamp,
	};
}

function expoRequest(options: LocationOptions, watching: boolean): LocationRequest {
	const accuracy = options.accuracy;
	return {
		highAccuracy: accuracy !== null && (accuracy as LocationAccuracy) >= LocationAccuracy.High,
		timeout: finiteOr(options.timeout ?? null, FOREVER),
		maximumAge: finiteOr(options.maximumAge ?? null, watching ? FOREVER : 0),
		distanceFilter: finiteOr(options.distanceInterval ?? null, 0),
		interval: finiteOr(options.timeInterval ?? null, 5000),
	};
}

function objectOrThrow(fix: LocationFix): LocationObject {
	if (fix.code !== 0) { throw new Error(fix.message); }
	return locationObject(fix);
}

export class Location {
	static async requestForegroundPermissionsAsync(): Promise<PermissionResponse> {
		return await Permissions.request("location");
	}

	static async getForegroundPermissionsAsync(): Promise<PermissionResponse> {
		return await Permissions.check("location");
	}

	static async getCurrentPositionAsync(options: LocationOptions = {}): Promise<LocationObject> {
		if (!(await authorized())) { return objectOrThrow(deniedFix()); }
		const fix = await new Promise<LocationFix>((resolve) => {
			locationServices("Location.getCurrentPositionAsync").locationCurrent(expoRequest(options, false), (current: LocationFix): void => {
				resolve(current);
			});
		});
		return objectOrThrow(fix);
	}

	static async watchPositionAsync(
		options: LocationOptions,
		callback: (location: LocationObject) => void,
	): Promise<LocationSubscription> {
		const id = nextWatch;
		nextWatch += 1;
		live.add(id);
		if (!(await authorized())) {
			live.delete(id);
			throw new Error("Location permission was not granted.");
		}
		started.add(id);
		locationServices("Location.watchPositionAsync").locationWatch(id, expoRequest(options, true), (fix: LocationFix): void => {
			if (fix.code === 0 && live.has(id)) { callback(locationObject(fix)); }
		});
		return { remove: (): void => { Geolocation.clearWatch(id as number); } };
	}
}
