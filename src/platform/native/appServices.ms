import { AlertRequest, AppServices, ShareRequest, installAppServices } from "../../api/services";
import { publishPlatform } from "../../api/platform";
import { publishScale, publishScreen } from "../../api/dimensions";
import { AppStateStatus, publishAppState, publishMemoryWarning } from "../../api/appState";
import { dispatchHardwareBackPress } from "../../api/backHandler";
import { publishUrl } from "../../api/linking";
import { publishReduceMotion, publishScreenReader } from "../../api/accessibilityInfo";
import {
	androidPermissionGranted, androidRequestPermissions, androidShouldShowRationale, locationClear, locationCurrent,
	locationWatch, onLocationEvent, onNetInfoEvent, onReplyEvent, permissionStatus, refreshNetInfo, requestPermission,
	storageClear, storageGet, storageKeys, storageRemove, storageSet, watchNetInfo,
} from "./deviceServices";

when (ios) {
	@compile("../ios/app.m", "-fobjc-arc");
	@compile("../ios/modules.m", "-fobjc-arc");
	@compile("../ios/storage.m", "-fobjc-arc");
	@compile("../ios/netinfo.m", "-fobjc-arc");
	@compile("../ios/permissions.m", "-fobjc-arc");
	@compile("../ios/location.m", "-fobjc-arc");
	@passL("-framework AudioToolbox");
	@passL("-framework Network");
	@passL("-framework AVFoundation");
	@passL("-framework CoreLocation");
	@passL("-framework UserNotifications");
} else when (android) {
	@compile("../android/app.c");
}

import { niAppCall, niLastAppEvent, niLastAppValue, niSetAppEventResult } from "./app.h";

extern function niSetAppHandler(handler: () => void): void;

const FIELD = "\u001f";
const RECORD = "\u001e";

enum AppEvent {
	State,
	BackPress,
	Alert,
	ScreenReader,
	Url,
	Share,
	MemoryWarning,
	ReduceMotion,
	ImageSize,
	Reply,
	NetInfo,
	Location,
}

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
	const reply: string = niAppCall(name, arg);
	return reply;
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
	match (niLastAppEvent() as AppEvent) {
		AppEvent.State => publishAppState(value as AppStateStatus),
		AppEvent.BackPress => niSetAppEventResult(dispatchHardwareBackPress() ? 1 : 0),
		AppEvent.Alert => settleAlert(value),
		AppEvent.ScreenReader => publishScreenReader(value === "1"),
		AppEvent.Url => publishUrl(value),
		AppEvent.Share => settleShare(value),
		AppEvent.MemoryWarning => publishMemoryWarning(),
		AppEvent.ReduceMotion => publishReduceMotion(value === "1"),
		AppEvent.ImageSize => settleImage(value),
		AppEvent.Reply => onReplyEvent(value),
		AppEvent.NetInfo => onNetInfoEvent(value),
		AppEvent.Location => onLocationEvent(value),
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

function imageSize(uri: string, done: (width: number, height: number, error: string) => void): void {
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

function vibrate(pattern: int32[], repeat: boolean): void {
	let steps = "";
	for (const step of pattern) { steps += (steps === "" ? "" : ",") + step.toString(); }
	call("vibrate", (repeat ? "1" : "0") + FIELD + steps);
}

const services: AppServices = {
	dismissKeyboard: (): void => { call("keyboard.dismiss", ""); },
	alert,
	openURL: async (url: string): Promise<boolean> => { return call("linking.open", url) === "1"; },
	canOpenURL: async (url: string): Promise<boolean> => { return call("linking.canOpen", url) === "1"; },
	initialURL: async (): Promise<string> => { return call("linking.initial", ""); },
	openSettings: async (): Promise<boolean> => { return call("linking.settings", "") === "1"; },
	share,
	vibrate,
	cancelVibration: (): void => { call("vibrate.cancel", ""); },
	getClipboard: async (): Promise<string> => { return call("clipboard.get", ""); },
	setClipboard: (text: string): void => { call("clipboard.set", text); },
	screenReaderEnabled: async (): Promise<boolean> => { return call("a11y.screenReader", "") === "1"; },
	reduceMotionEnabled: async (): Promise<boolean> => { return call("a11y.reduceMotion", "") === "1"; },
	announce: (text: string): void => { call("a11y.announce", text); },
	exitApp: (): void => { call("exitApp", ""); },
	imageSize,
	storageGet,
	storageSet,
	storageRemove,
	storageClear,
	storageKeys,
	watchNetInfo,
	refreshNetInfo,
	permissionStatus,
	requestPermission,
	androidPermissionGranted,
	androidShouldShowRationale,
	androidRequestPermissions,
	locationCurrent,
	locationWatch,
	locationClear,
};

export function installNativeAppServices(run: (fn: () => void) => void): void {
	runEvent = run;
	niSetAppHandler(onAppEventBatched);
	installAppServices(services);
	publishPlatform(call("platform", ""), call("isPad", "") === "1");
	publishScale(parseFloat(call("pixelRatio", "")), parseFloat(call("fontScale", "")));
	const screen = call("screen", "").split(FIELD);
	if (screen.length === 2) { publishScreen(parseFloat(screen[0]), parseFloat(screen[1])); }
	const state = call("appState", "");
	if (state !== "") { publishAppState(state as AppStateStatus); }
	publishScreenReader(call("a11y.screenReader", "") === "1");
	publishReduceMotion(call("a11y.reduceMotion", "") === "1");
}
