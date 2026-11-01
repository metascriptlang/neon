import { LocationFix, LocationRequest, LocationServices, installLocationServices } from "../../api/locationServices";
import { AppCommand, AppEvent, FIELD, appCall, onNativeAppEvent, requestReply, wireId, wireInt, wirePayload } from "./appBridge";
import { niLocationCommand } from "./commands.h";
import { androidLibrary } from "../../../../ion/src/android";

when (ios) {
	@compile("../ios/location.m", "-fobjc-arc");
	@compile("../ios/wire.m", "-fobjc-arc");
	@passL("-framework CoreLocation");
} else when (android) {
	androidLibrary("../android/geolocation");
}

when (ios || android) {
	function command(name: string, arg: string): string {
		return niLocationCommand(name, arg) as string;
	}
} else {
	const command: AppCommand = appCall;
}

function measured(text: string): number {
	return text === "" ? NaN : parseFloat(text);
}

function decodeFix(value: string): LocationFix {
	const fields = value.split(FIELD);
	if (fields[0] === "error" && fields.length === 3) {
		return {
			code: wireInt("Geolocation", "error code", fields[1]),
			message: fields[2],
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
	if (fields[0] !== "ok" || fields.length !== 9) {
		throw new Error("Geolocation: the host sent a malformed fix: " + value);
	}
	return {
		code: 0,
		message: "",
		latitude: parseFloat(fields[1]),
		longitude: parseFloat(fields[2]),
		altitude: measured(fields[3]),
		accuracy: measured(fields[4]),
		altitudeAccuracy: measured(fields[5]),
		heading: measured(fields[6]),
		speed: measured(fields[7]),
		timestamp: parseFloat(fields[8]),
	};
}

function encodeRequest(request: LocationRequest): string {
	return (request.highAccuracy ? "1" : "0") + FIELD + request.timeout.toString() + FIELD +
		request.maximumAge.toString() + FIELD + request.distanceFilter.toString() + FIELD + request.interval.toString();
}

interface LocationWatch {
	id: int32;
	update: (fix: LocationFix) => void;
}

const watches: LocationWatch[] = [];

function locationCurrent(request: LocationRequest, done: (fix: LocationFix) => void): void {
	requestReply(command, "location.current", encodeRequest(request), (reply: string): void => { done(decodeFix(reply)); });
}

function locationWatch(id: int32, request: LocationRequest, update: (fix: LocationFix) => void): void {
	watches.push({ id, update });
	command("location.watch", id.toString() + FIELD + encodeRequest(request));
}

function locationClear(id: int32): void {
	for (let i = 0; i < watches.length; i += 1) {
		if (watches[i].id === id) {
			watches.splice(i, 1);
			command("location.clear", id.toString());
			return;
		}
	}
}

function onLocationEvent(value: string): void {
	const id = wireId("Geolocation", value);
	for (const watch of watches.slice(0, watches.length)) {
		if (watch.id === id) { watch.update(decodeFix(wirePayload(value))); }
	}
}

export const nativeLocationServices: LocationServices = { locationCurrent, locationWatch, locationClear };

installLocationServices(nativeLocationServices);
onNativeAppEvent(AppEvent.Location, onLocationEvent);
