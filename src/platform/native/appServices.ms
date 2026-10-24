import { AlertRequest, AppServices, ShareRequest, installAppServices } from "../../api/services";
import { publishPlatform } from "../../api/platform";
import { publishScale, publishScreen } from "../../api/dimensions";
import { AppStateStatus, publishAppState, publishMemoryWarning } from "../../api/appState";
import { dispatchHardwareBackPress } from "../../api/backHandler";
import {
	AppEvent, FIELD, RECORD, appCall, dispatchNativeAppEvent, runNativeAppStarts,
} from "./appBridge";
import { CaptureServices, installCaptureServices } from "../../api/captureServices";

when (ios) {
	@compile("../ios/app.m", "-fobjc-arc");
	@compile("../ios/wire.m", "-fobjc-arc");
	@compile("../ios/modules.m", "-fobjc-arc");
	@compile("../ios/capture.m", "-fobjc-arc");
	@compile("../ios/audio.m", "-fobjc-arc");
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

function call(name: string, arg: string): string {
	return appCall(name, arg);
}

function settleAlert(value: string): void {
	const fields = value.split(FIELD);
	const id = parseInt(fields[0]) as int32;
	const index = parseInt(fields[1]) as int32;
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
	const value: string = niLastAppValue();
	const kind = niLastAppEvent() as AppEvent;
	match (kind) {
		AppEvent.State => publishAppState(value as AppStateStatus),
		AppEvent.BackPress => niSetAppEventResult(dispatchHardwareBackPress() ? 1 : 0),
		AppEvent.Alert => settleAlert(value),
		AppEvent.Share => settleShare(value),
		AppEvent.MemoryWarning => publishMemoryWarning(),
		AppEvent.ImageSize => settleImage(value),
		_ => dispatchNativeAppEvent(kind, value),
	};
}

function settleImage(value: string): void {
	const fields = value.split(FIELD);
	const id = parseInt(fields[0]) as int32;
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
	call("image.size", id.toString() + FIELD + uri);
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
	call("alert", arg);
}

function share(request: ShareRequest): void {
	const reply = call("share", request.title + FIELD + request.message + FIELD + request.url);
	if (reply !== "") {
		request.done(reply, "");
		return;
	}
	shares.push(request.done);
}

const services: AppServices = {
	dismissKeyboard: (): void => { call("keyboard.dismiss", ""); },
	alert,
	share,
	announce: (text: string): void => { call("a11y.announce", text); },
	exitApp: (): void => { call("exitApp", ""); },
	imageSize,
};

when (macos && !testBuild) {
	let capture: CaptureServices | null = null;
} else {
	import { nativeCaptureServices } from "./captureServices";
	let capture: CaptureServices | null = nativeCaptureServices;
}
let app: AppServices = services;

// A desktop owner that runs the audio device itself (Ion) answers capture in place of the bridge.
export function useCaptureServices(services: CaptureServices): void {
	capture = services;
}

// A desktop owner (Ion) answers the app services in place of the bridge, as it does capture.
export function useAppServices(owned: AppServices): void {
	app = owned;
}

export function installNativeAppServices(run: (fn: () => void) => void): void {
	runEvent = run;
	niSetAppHandler(onAppEventBatched);
	installAppServices(app);
	installCaptureServices(capture);
	publishPlatform(call("platform", ""), call("isPad", "") === "1");
	publishScale(parseFloat(call("pixelRatio", "")), parseFloat(call("fontScale", "")));
	const screen = call("screen", "").split(FIELD);
	if (screen.length === 2) { publishScreen(parseFloat(screen[0]), parseFloat(screen[1])); }
	const state = call("appState", "");
	if (state !== "") { publishAppState(state as AppStateStatus); }
	runNativeAppStarts();
}
