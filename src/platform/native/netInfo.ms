import {
	NetInfoDetails, NetInfoServices, NetInfoState, NetInfoStateType, installNetInfoServices, netInfoEvent,
} from "../../api/netInfoServices";
import { AppEvent, FIELD, appCall, onNativeAppEvent } from "./appBridge";
import { niNetInfoCommand } from "./commands.h";
import { androidLibrary } from "../../../../ion/src/android";

when (ios) {
	@compile("../ios/netinfo.m", "-fobjc-arc");
	@passL("-framework Network");
} else when (android) {
	androidLibrary("../android/netInfo");
}

when (ios || android) {
	function command(name: string, arg: string): string {
		const reply: string = niNetInfoCommand(name, arg);
		return reply;
	}
} else {
	function command(name: string, arg: string): string {
		return appCall(name, arg);
	}
}

function flag(text: string): boolean | null {
	if (text === "") { return null; }
	return text === "1";
}

function decodeNetInfo(value: string): NetInfoState {
	const fields = value.split(FIELD);
	if (fields.length !== 4) { throw new Error("NetInfo: the host sent a malformed state: " + value); }
	const type = fields[0] as NetInfoStateType;
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
