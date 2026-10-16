import { flush } from "../core/runtime";
import { Dispose } from "../core/types";

export enum RoutingError {
	NoMatch,
	InvalidAddress,
	InvalidParams,
	DuplicateScope,
	UnknownScope,
	AmbiguousRoute,
	IncompleteSnapshot,
	Refused,
}

export interface RouteCodec<P> {
	id: string;
	decode: (address: string) => Result<P, RoutingError>;
	encode: (params: P) => Result<string, RoutingError>;
}

export interface RoutePlan {
	commit: () => void;
}

export interface RouteBinding {
	id: string;
	prepare: (address: string) => Result<RoutePlan, RoutingError>;
	address: () => Result<string | null, RoutingError>;
}

export function bindRoute<P>(
	codec: RouteCodec<P>,
	current: () => P | null,
	apply: (params: P) => void,
): RouteBinding {
	if (codec.id === "") { throw new Error("routing: empty route identity"); }
	return {
		id: codec.id,
		prepare: (address: string): Result<RoutePlan, RoutingError> => {
			const decoded = codec.decode(address);
			if (!decoded.ok) { return Result.err(decoded.error); }
			const params = decoded.value;
			return Result.ok({ commit: (): void => apply(params) });
		},
		address: (): Result<string | null, RoutingError> => {
			const params = current();
			if (params === null) { return Result.ok(null); }
			const encoded = codec.encode(params as P);
			if (!encoded.ok) { return Result.err(encoded.error); }
			const address: string | null = encoded.value;
			return Result.ok(address);
		},
	};
}

function hexValue(byte: int32): int32 {
	if (byte >= 48 && byte <= 57) { return byte - 48; }
	if (byte >= 65 && byte <= 70) { return byte - 55; }
	if (byte >= 97 && byte <= 102) { return byte - 87; }
	return -1;
}

export function encodeRouteComponent(value: string): string {
	const hex = "0123456789ABCDEF";
	let encoded = "";
	for (let i = 0; i < value.byteLength(); i += 1) {
		const byte = value.byteAt(i);
		if ((byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) ||
			(byte >= 48 && byte <= 57) || byte === 45 || byte === 46 ||
			byte === 95 || byte === 126) {
			encoded += String.fromCharCode(byte);
		} else {
			encoded += "%" + hex.substring(byte / 16, byte / 16 + 1) +
				hex.substring(byte % 16, byte % 16 + 1);
		}
	}
	return encoded;
}

function validUtf8(bytes: uint8[]): boolean {
	let i: int32 = 0;
	while (i < bytes.length) {
		const lead = bytes[i] as int32;
		if (lead < 128) { i += 1; continue; }
		let count: int32 = 0;
		if (lead >= 194 && lead <= 223) { count = 2; }
		else if (lead >= 224 && lead <= 239) { count = 3; }
		else if (lead >= 240 && lead <= 244) { count = 4; }
		else { return false; }
		if (i + count > bytes.length) { return false; }
		const second = bytes[i + 1] as int32;
		if ((lead === 224 && second < 160) || (lead === 237 && second >= 160) ||
			(lead === 240 && second < 144) || (lead === 244 && second >= 144)) {
			return false;
		}
		for (let j = 1; j < count; j += 1) {
			const byte = bytes[i + j] as int32;
			if (byte < 128 || byte > 191) { return false; }
		}
		i += count;
	}
	return true;
}

export function decodeRouteComponent(value: string): Result<string, RoutingError> {
	const bytes: uint8[] = [];
	let i: int32 = 0;
	while (i < value.byteLength()) {
		const byte = value.byteAt(i);
		if (byte === 37) {
			if (i + 2 >= value.byteLength()) { return Result.err(RoutingError.InvalidAddress); }
			const high = hexValue(value.byteAt(i + 1));
			const low = hexValue(value.byteAt(i + 2));
			if (high < 0 || low < 0) { return Result.err(RoutingError.InvalidAddress); }
			bytes.push((high * 16 + low) as uint8);
			i += 3;
		} else {
			bytes.push(byte as uint8);
			i += 1;
		}
	}
	if (!validUtf8(bytes)) { return Result.err(RoutingError.InvalidAddress); }
	return Result.ok(bytes.asString());
}

export struct RegionAddress {
	scope: string;
	address: string;
}

export struct RegionSnapshot {
	scope: string;
	state: string;
}

export struct RoutingSnapshot {
	regions: RegionSnapshot[];
}

export interface RoutingParticipant {
	scope: string;
	prepare: (address: string | null) => Result<RoutePlan, RoutingError>;
	address: () => Result<string | null, RoutingError>;
	capture: () => string;
	restore: (state: string) => Result<RoutePlan, RoutingError>;
}

const REGION_PREFIX = "__nav.";

function validScope(scope: string): boolean {
	if (scope === "") { return false; }
	for (let i = 0; i < scope.byteLength(); i += 1) {
		const byte = scope.byteAt(i);
		if (!((byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) ||
			(byte >= 48 && byte <= 57) || byte === 45 || byte === 46 || byte === 95)) {
			return false;
		}
	}
	return true;
}

function validAddress(address: string): boolean {
	if (!address.startsWith("/") || address.startsWith("//")) { return false; }
	const decoded = decodeRouteComponent(address);
	if (!decoded.ok) { return false; }
	const value = decoded.value;
	for (let i = 0; i < value.byteLength(); i += 1) {
		const byte = value.byteAt(i);
		if (byte < 32 || byte === 127 || byte === 92) { return false; }
	}
	return true;
}

export function decodeRoutingLocation(
	primaryScope: string,
	url: string,
): Result<RegionAddress[], RoutingError> {
	if (!validScope(primaryScope) || !validAddress(url)) {
		return Result.err(RoutingError.InvalidAddress);
	}
	const hashAt = url.indexOf("#");
	const hash = hashAt < 0 ? "" : url.substring(hashAt, url.length);
	const withoutHash = hashAt < 0 ? url : url.substring(0, hashAt);
	const queryAt = withoutHash.indexOf("?");
	const pathname = queryAt < 0 ? withoutHash : withoutHash.substring(0, queryAt);
	const query = queryAt < 0 ? "" : withoutHash.substring(queryAt + 1, withoutHash.length);
	const regions: RegionAddress[] = [];
	const scopes = new Set<string>();
	scopes.add(primaryScope);
	const remaining: string[] = [];
	for (const pair of query.split("&")) {
		if (pair === "") { continue; }
		const equalAt = pair.indexOf("=");
		const name = equalAt < 0 ? pair : pair.substring(0, equalAt);
		const key = try decodeRouteComponent(name);
		if (!key.startsWith(REGION_PREFIX)) { remaining.push(pair); continue; }
		if (equalAt < 0) { return Result.err(RoutingError.InvalidAddress); }
		const scope = key.substring(REGION_PREFIX.length, key.length);
		if (!validScope(scope)) { return Result.err(RoutingError.InvalidAddress); }
		if (scopes.has(scope)) { return Result.err(RoutingError.DuplicateScope); }
		const address = try decodeRouteComponent(pair.substring(equalAt + 1, pair.length));
		if (!validAddress(address)) { return Result.err(RoutingError.InvalidAddress); }
		scopes.add(scope);
		regions.push({ scope, address });
	}
	const primary = pathname + (remaining.length > 0 ? "?" + remaining.join("&") : "") + hash;
	const result: RegionAddress[] = [{ scope: primaryScope, address: primary }];
	for (const region of regions) { result.push(region); }
	return Result.ok(result);
}

export function encodeRoutingLocation(
	primaryScope: string,
	regions: RegionAddress[],
): Result<string, RoutingError> {
	const addresses = new Map<string, string>();
	const scopes: string[] = [];
	for (const region of regions) {
		if (!validScope(region.scope) || !validAddress(region.address)) {
			return Result.err(RoutingError.InvalidAddress);
		}
		if (addresses.has(region.scope)) { return Result.err(RoutingError.DuplicateScope); }
		addresses.set(region.scope, region.address);
		if (region.scope !== primaryScope) { scopes.push(region.scope); }
	}
	const primary = addresses.get(primaryScope);
	if (primary === null) { return Result.err(RoutingError.NoMatch); }
	const value = primary as string;
	const checked = try decodeRoutingLocation(primaryScope, value);
	if (checked.length !== 1) { return Result.err(RoutingError.DuplicateScope); }
	const hashAt = value.indexOf("#");
	let url = hashAt < 0 ? value : value.substring(0, hashAt);
	const hash = hashAt < 0 ? "" : value.substring(hashAt, value.length);
	scopes.sort();
	for (const scope of scopes) {
		url += (url.indexOf("?") < 0 ? "?" : "&") + REGION_PREFIX + scope + "=" +
			encodeRouteComponent(addresses.get(scope) as string);
	}
	return Result.ok(url + hash);
}

export class RoutingRegistry {
	private primaryScope: string;
	private participants: RoutingParticipant[] = [];

	constructor(primaryScope: string) {
		if (!validScope(primaryScope)) {
			throw new Error("routing: invalid primary scope: " + primaryScope);
		}
		this.primaryScope = primaryScope;
	}

	register(participant: RoutingParticipant): Dispose {
		if (!validScope(participant.scope)) {
			throw new Error("routing: invalid scope: " + participant.scope);
		}
		for (const registered of this.participants) {
			if (registered.scope === participant.scope) {
				throw new Error("duplicate routing scope: " + participant.scope);
			}
		}
		this.participants.push(participant);
		let removed = false;
		return (): void => {
			if (removed) { return; }
			removed = true;
			const kept: RoutingParticipant[] = [];
			for (const registered of this.participants) {
				if (registered !== participant) { kept.push(registered); }
			}
			this.participants = kept;
		};
	}

	prepare(url: string): Result<RoutePlan, RoutingError> {
		const regions = try decodeRoutingLocation(this.primaryScope, url);
		const requested = new Map<string, string>();
		for (const region of regions) {
			let known = false;
			for (const participant of this.participants) {
				if (participant.scope === region.scope) { known = true; break; }
			}
			if (!known) { return Result.err(RoutingError.UnknownScope); }
			requested.set(region.scope, region.address);
		}
		const plans: RoutePlan[] = [];
		for (const participant of this.participants) {
			plans.push(try participant.prepare(requested.get(participant.scope)));
		}
		return Result.ok({ commit: (): void => {
			flush((): void => { for (const plan of plans) { plan.commit(); } });
		} });
	}

	apply(url: string): Result<void, RoutingError> {
		const plan = try this.prepare(url);
		plan.commit();
		return Result.ok(null);
	}

	address(): Result<string, RoutingError> {
		const regions: RegionAddress[] = [];
		for (const participant of this.participants) {
			const address = try participant.address();
			if (address !== null) {
				regions.push({ scope: participant.scope, address: address as string });
			}
		}
		return encodeRoutingLocation(this.primaryScope, regions);
	}

	capture(): RoutingSnapshot {
		const regions: RegionSnapshot[] = [];
		for (const participant of this.participants) {
			regions.push({ scope: participant.scope, state: participant.capture() });
		}
		return { regions };
	}

	prepareRestore(snapshot: RoutingSnapshot): Result<RoutePlan, RoutingError> {
		if (snapshot.regions.length !== this.participants.length) {
			return Result.err(RoutingError.IncompleteSnapshot);
		}
		const states = new Map<string, string>();
		for (const region of snapshot.regions) {
			if (states.has(region.scope)) { return Result.err(RoutingError.DuplicateScope); }
			states.set(region.scope, region.state);
		}
		const plans: RoutePlan[] = [];
		for (const participant of this.participants) {
			const state = states.get(participant.scope);
			if (state === null) { return Result.err(RoutingError.IncompleteSnapshot); }
			plans.push(try participant.restore(state as string));
		}
		return Result.ok({ commit: (): void => {
			flush((): void => { for (const plan of plans) { plan.commit(); } });
		} });
	}

	restore(snapshot: RoutingSnapshot): Result<void, RoutingError> {
		const plan = try this.prepareRestore(snapshot);
		plan.commit();
		return Result.ok(null);
	}
}

export function createRouteParticipant(
	scope: string,
	bindings: RouteBinding[],
	clear: () => void,
	capture: () => string,
	restore: (state: string) => Result<RoutePlan, RoutingError>,
): RoutingParticipant {
	const ids = new Set<string>();
	const routes = bindings.slice(0);
	for (const binding of routes) {
		if (ids.has(binding.id)) { throw new Error("duplicate route identity: " + binding.id); }
		ids.add(binding.id);
	}
	return {
		scope,
		prepare: (address: string | null): Result<RoutePlan, RoutingError> => {
			if (address === null) { return Result.ok({ commit: clear }); }
			const plans: RoutePlan[] = [];
			for (const binding of routes) {
				const plan = binding.prepare(address as string);
				if (plan.ok) { plans.push(plan.value); }
				else if (plan.error !== RoutingError.NoMatch) { return Result.err(plan.error); }
			}
			if (plans.length === 0) { return Result.err(RoutingError.NoMatch); }
			if (plans.length > 1) { return Result.err(RoutingError.AmbiguousRoute); }
			return Result.ok(plans[0]);
		},
		address: (): Result<string | null, RoutingError> => {
			let active: string | null = null;
			for (const binding of routes) {
				const address = try binding.address();
				if (address === null) { continue; }
				if (active !== null) { return Result.err(RoutingError.AmbiguousRoute); }
				active = address;
			}
			return Result.ok(active);
		},
		capture,
		restore,
	};
}
