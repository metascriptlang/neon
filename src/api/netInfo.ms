import { Accessor, createSignal } from "../core/signal";
import { onChange } from "./subscription";
import { appServices, appServicesGeneration } from "./services";

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

export type NetInfoChangeHandler = (state: NetInfoState) => void;
export type NetInfoUnsubscribe = () => void;

const UNKNOWN: NetInfoState = { type: "unknown", isConnected: null, isInternetReachable: null, details: null };

const [current, setCurrent] = createSignal<NetInfoState>(UNKNOWN);
let watchedBy: int32 = -1;

function watch(api: string): void {
	const services = appServices(api);
	if (watchedBy === appServicesGeneration()) { return; }
	watchedBy = appServicesGeneration();
	services.watchNetInfo();
}

function sameFlag(a: boolean | null, b: boolean | null): boolean {
	if (a === null || b === null) { return a === null && b === null; }
	return (a as boolean) === (b as boolean);
}

function expensive(state: NetInfoState): boolean {
	const details = state.details;
	return details !== null && details.isConnectionExpensive;
}

function same(a: NetInfoState, b: NetInfoState): boolean {
	const aType: string = a.type;
	const bType: string = b.type;
	return aType === bType && sameFlag(a.isConnected, b.isConnected) &&
		sameFlag(a.isInternetReachable, b.isInternetReachable) && expensive(a) === expensive(b) &&
		(a.details === null) === (b.details === null);
}

export class NetInfo {
	static async fetch(): Promise<NetInfoState> {
		watch("NetInfo.fetch");
		appServices("NetInfo.fetch").refreshNetInfo();
		return current();
	}

	static async refresh(): Promise<NetInfoState> {
		return await NetInfo.fetch();
	}

	static addEventListener(listener: NetInfoChangeHandler): NetInfoUnsubscribe {
		watch("NetInfo.addEventListener");
		const subscription = onChange(current, listener);
		listener(current());
		return subscription.remove;
	}
}

export function useNetInfo(): Accessor<NetInfoState> {
	watch("useNetInfo");
	return current;
}

export function publishNetInfo(next: NetInfoState): void {
	if (!same(current(), next)) { setCurrent(next); }
}
