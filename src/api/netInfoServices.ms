export type NetInfoStateType =
	"unknown" | "none" | "cellular" | "wifi" | "bluetooth" | "ethernet" | "wimax" | "vpn" | "other";

export interface NetInfoDetails {
	isConnectionExpensive: boolean;
}

export interface NetInfoState {
	type: NetInfoStateType;
	isConnected: boolean | null;
	isInternetReachable: boolean | null;
	details: NetInfoDetails | null;
}

export interface NetInfoServices {
	watchNetInfo: () => void;
	refreshNetInfo: () => void;
}

let installed: NetInfoServices | null = null;
let generation: int32 = 0;
let listener: (state: NetInfoState) => void = (state: NetInfoState): void => {};

export function installNetInfoServices(services: NetInfoServices | null): void {
	installed = services;
	generation += 1;
}

export function netInfoServicesGeneration(): int32 {
	return generation;
}

export function netInfoServices(api: string): NetInfoServices {
	const services = installed;
	if (services === null) { throw new Error(`${api} is not available on this host`); }
	return services;
}

export function listenNetInfo(next: (state: NetInfoState) => void): void {
	listener = next;
}

export function netInfoEvent(state: NetInfoState): void {
	listener(state);
}
