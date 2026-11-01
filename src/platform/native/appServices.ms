import { AlertRequest, AppServices, ShareRequest, installAppServices } from "../../api/services";
import { publishPlatform } from "../../api/platform";
import { publishScale, publishScreen } from "../../api/dimensions";
import { AppStateStatus, publishAppState, publishMemoryWarning } from "../../api/appState";
import { dispatchHardwareBackPress } from "../../api/backHandler";
import {
	AppEvent, FIELD, PENDING_REPLY, RECORD, appCall, appEventOf, dispatchNativeAppEvent, runNativeAppStarts, wireFields, wireInt,
} from "./appBridge";
import { CaptureServices, installCaptureServices } from "../../api/captureServices";

when (ios) {
	@compile("../ios/app.m", "-fobjc-arc");
	@compile("../ios/wire.m", "-fobjc-arc");
	@compile("../ios/modules.m", "-fobjc-arc");
	@compile("../ios/capture.m", "-fobjc-arc");
	@compile("../ios/audio.m", "-fobjc-arc");
	@compile("../ios/actionSheet.m", "-fobjc-arc");
	@compile("../ios/settings.m", "-fobjc-arc");
	@passL("-framework PhotosUI");
	@passL("-framework UniformTypeIdentifiers");
	@passL("-framework CoreMedia");
	@passL("-framework AVFoundation");
} else when (android) {
	@compile("../android/app.c");
}

import { niLastAppEvent, niLastAppValue, niSetAppEventResult } from "./app.h";

extern function niSetAppHandler(handler: () => void): void;

interface PendingImage {
	id: int32;
	done: (width: number, height: number, error: string) => void;
}

const images: PendingImage[] = [];

interface PendingAlert {
	id: int32;
	done: (index: int32) => void;
}

const alerts: PendingAlert[] = [];
const shares: ((action: string, activityType: string) => void)[] = [];
let nextRequest: int32 = 1;

function appStateOf(value: string): AppStateStatus {
	return match (value) {
		"active" => "active",
		"background" => "background",
		"inactive" => "inactive",
		"unknown" => "unknown",
		"extension" => "extension",
		_ => { throw new Error("App state: the host sent the unknown state " + value); },
	};
}

function settleAlert(value: string): void {
	const fields = wireFields("Alert", value, 2);
	const id = wireInt("Alert", "request id", fields[0]);
	const index = wireInt("Alert", "button index", fields[1]);
	for (let i = 0; i < alerts.length; i += 1) {
		if (alerts[i].id === id) {
			const pending = alerts[i];
			alerts.splice(i, 1);
			pending.done(index);
			return;
		}
	}
}

function settleShare(value: string): void {
	const fields = value.split(FIELD);
	if (shares.length === 0) { return; }
	const done = shares[0];
	shares.splice(0, 1);
	done(fields[0], fields.length > 1 ? fields[1] : "");
}

function onAppEvent(): void {
	const value: string = niLastAppValue() as string;
	const kind = appEventOf(niLastAppEvent());
	match (kind) {
		AppEvent.State => publishAppState(appStateOf(value)),
		AppEvent.BackPress => niSetAppEventResult(dispatchHardwareBackPress() ? 1 : 0),
		AppEvent.Alert => settleAlert(value),
		AppEvent.Share => settleShare(value),
		AppEvent.MemoryWarning => publishMemoryWarning(),
		AppEvent.ImageSize => settleImage(value),
		_ => dispatchNativeAppEvent(kind, value),
	};
}

function settleImage(value: string): void {
	const fields = wireFields("Image size", value, 3);
	const id = wireInt("Image size", "request id", fields[0]);
	for (let i = 0; i < images.length; i += 1) {
		if (images[i].id === id) {
			const pending = images[i];
			images.splice(i, 1);
			const error = fields.length > 3 ? fields[3] : "";
			pending.done(error === "" ? parseFloat(fields[1]) : 0, error === "" ? parseFloat(fields[2]) : 0, error);
			return;
		}
	}
}

export function imageSize(uri: string, done: (width: number, height: number, error: string) => void): void {
	const id = nextRequest;
	nextRequest += 1;
	images.push({ id, done });
	appCall("image.size", id.toString() + FIELD + uri);
}

let runEvent: (fn: () => void) => void = (fn: () => void): void => { fn(); };

function onAppEventBatched(): void {
	runEvent(onAppEvent);
}

function alert(request: AlertRequest): void {
	const id = nextRequest;
	nextRequest += 1;
	alerts.push({ id, done: request.done });
	let arg = id.toString() + FIELD + request.title + FIELD + request.message + FIELD +
		(request.cancelable ? "1" : "0");
	for (const button of request.buttons) { arg += RECORD + button.text + FIELD + button.style; }
	appCall("alert", arg);
}

function share(request: ShareRequest): void {
	const reply = appCall("share", request.title + FIELD + request.message + FIELD + request.url);
	if (reply !== PENDING_REPLY) {
		request.done(reply, "");
		return;
	}
	shares.push(request.done);
}

const services: AppServices = {
	dismissKeyboard: (): void => { appCall("keyboard.dismiss", ""); },
	alert,
	share,
	announce: (text: string): void => { appCall("a11y.announce", text); },
	exitApp: (): void => { appCall("exitApp", ""); },
	imageSize,
};

when (macos && !testBuild) {
	let capture: CaptureServices | null = null;
} else {
	import { nativeCaptureServices } from "./captureServices";
	let capture: CaptureServices | null = nativeCaptureServices;
}
let app: AppServices = services;

export function useCaptureServices(services: CaptureServices): void {
	capture = services;
}

export function useAppServices(owned: AppServices): void {
	app = owned;
}

export function installNativeAppServices(run: (fn: () => void) => void): void {
	runEvent = run;
	niSetAppHandler(onAppEventBatched);
	installAppServices(app);
	installCaptureServices(capture);
	publishPlatform(appCall("platform", ""), appCall("isPad", "") === "1");
	const ratio = appCall("pixelRatio", "");
	const font = appCall("fontScale", "");
	if (ratio !== "" && font !== "") { publishScale(parseFloat(ratio), parseFloat(font)); }
	const screen = appCall("screen", "").split(FIELD);
	if (screen.length === 2) { publishScreen(parseFloat(screen[0]), parseFloat(screen[1])); }
	const state = appCall("appState", "");
	if (state !== "") { publishAppState(appStateOf(state)); }
	runNativeAppStarts();
}
