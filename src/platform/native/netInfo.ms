import {
	NetInfoDetails, NetInfoServices, NetInfoState, NetInfoStateType, installNetInfoServices, netInfoEvent,
} from "../../api/netInfoServices";
import { AppCommand, AppEvent, FIELD, appCall, onNativeAppEvent } from "./appBridge";
import { niNetInfoCommand } from "./commands.h";
import { androidLibrary } from "../../../../ion/src/android";

when (ios) {
	@compile("../ios/netinfo.m", "-fobjc-arc");
	@compile("../ios/wire.m", "-fobjc-arc");
	@passL("-framework Network");
} else when (android) {
	androidLibrary("../android/netInfo");
}

when (ios || android) {
	function command(name: string, arg: string): string {
		return niNetInfoCommand(name, arg);
	}
} else {
	const command: AppCommand = appCall;
}

function flag(text: string): boolean | null {
	if (text === "") { return null; }
	return text === "1";
}

function netInfoTypeOf(value: string): NetInfoStateType {
	return match (value) {
		"unknown" => "unknown",
		"none" => "none",
		"cellular" => "cellular",
		"wifi" => "wifi",
		"bluetooth" => "bluetooth",
		"ethernet" => "ethernet",
		"wimax" => "wimax",
		"vpn" => "vpn",
		"other" => "other",
		_ => { throw new Error("NetInfo: the host sent the unknown connection type " + value); },
	};
}

function decodeNetInfo(value: string): NetInfoState {
	const fields = value.split(FIELD);
	if (fields.length !== 4) { throw new Error("NetInfo: the host sent a malformed state: " + value); }
	const type = netInfoTypeOf(fields[0]);
	const connected = flag(fields[1]);
	const details: NetInfoDetails | null = connected === true ? { isConnectionExpensive: fields[3] === "1" } : null;
	return { type, isConnected: connected, isInternetReachable: flag(fields[2]), details };
}

function watchNetInfo(): void {
	netInfoEvent(decodeNetInfo(command("netinfo.watch", "")));
}

function refreshNetInfo(): void {
	netInfoEvent(decodeNetInfo(command("netinfo.fetch", "")));
}

function onNetInfoEvent(value: string): void {
	netInfoEvent(decodeNetInfo(value));
}

export const nativeNetInfoServices: NetInfoServices = { watchNetInfo, refreshNetInfo };

installNetInfoServices(nativeNetInfoServices);
onNativeAppEvent(AppEvent.NetInfo, onNetInfoEvent);
