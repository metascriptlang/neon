import {
	RouteCodec,
	RoutingError,
	bindRoute,
	encodeRouteComponent,
	decodeRouteComponent,
	RoutingRegistry,
	RoutingParticipant,
	RoutePlan,
	decodeRoutingLocation,
	encodeRoutingLocation,
} from "../../src/navigation/routing";

struct ItemParams {
	id: string;
}

const itemRoute: RouteCodec<ItemParams> = {
	id: "item",
	decode: (address: string): Result<ItemParams, RoutingError> => {
		if (!address.startsWith("/items/")) { return Result.err(RoutingError.NoMatch); }
		const id = try decodeRouteComponent(address.substring(7, address.length));
		if (id === "" || id.indexOf("/") >= 0) { return Result.err(RoutingError.InvalidParams); }
		return Result.ok({ id });
	},
	encode: (params: ItemParams): Result<string, RoutingError> => {
		if (params.id === "" || params.id.indexOf("/") >= 0) {
			return Result.err(RoutingError.InvalidParams);
		}
		return Result.ok("/items/" + encodeRouteComponent(params.id));
	},
};

test "typed route bindings validate before applying and do not erase params" {
	let current: ItemParams | null = null;
	const binding = bindRoute<ItemParams>(
		itemRoute,
		(): ItemParams | null => current,
		(params: ItemParams): void => { current = params; },
	);
	const planned = binding.prepare("/items/caf%C3%A9");
	assert planned.ok;
	assert current === null;
	if (planned.ok) { planned.value.commit(); }
	assert current !== null;
	if (current !== null) { assert (current as ItemParams).id === "café"; }
	const address = binding.address();
	assert address.ok;
	if (address.ok) { assert address.value === "/items/caf%C3%A9"; }
	const invalid = binding.prepare("/items/");
	assert !invalid.ok;
	if (!invalid.ok) { assert invalid.error === RoutingError.InvalidParams; }
	const missing = binding.prepare("/settings");
	assert !missing.ok;
	if (!missing.ok) { assert missing.error === RoutingError.NoMatch; }
}

test "route components encode UTF-8 and reject malformed escapes and invalid UTF-8" {
	assert encodeRouteComponent("café /?&=#") === "caf%C3%A9%20%2F%3F%26%3D%23";
	const decoded = decodeRouteComponent("caf%C3%A9%20%2F%3F%26%3D%23");
	assert decoded.ok;
	if (decoded.ok) { assert decoded.value === "café /?&=#"; }
	const truncated = decodeRouteComponent("%2");
	const badHex = decodeRouteComponent("%zz");
	const badUtf8 = decodeRouteComponent("%C0%AF");
	assert !truncated.ok && !badHex.ok && !badUtf8.ok;
}

test "scoped location encoding preserves primary query/hash and addresses parallel regions" {
	const encoded = encodeRoutingLocation("main", [
		{ scope: "main", address: "/editor/7?document=42#preview" },
		{ scope: "inspector", address: "/material/café?tab=colors" },
	]);
	assert encoded.ok;
	if (encoded.ok) {
		const expected = "/editor/7?document=42&__nav.inspector=" +
			"%2Fmaterial%2Fcaf%C3%A9%3Ftab%3Dcolors#preview";
		assert encoded.value === expected, encoded.value;
		const decoded = decodeRoutingLocation("main", encoded.value);
		assert decoded.ok;
		if (decoded.ok) {
			assert decoded.value[0].address === "/editor/7?document=42#preview";
			assert decoded.value[1].scope === "inspector";
			assert decoded.value[1].address === "/material/café?tab=colors";
		}
	}
	const duplicate = decodeRoutingLocation("main", "/?__nav.inspector=%2Fa&__nav.inspector=%2Fb");
	assert !duplicate.ok;
	const external = decodeRoutingLocation("main", "//example.com");
	assert !external.ok;
}

function textParticipant(
	scope: string,
	read: () => string,
	write: (value: string) => void,
): RoutingParticipant {
	return {
		scope,
		prepare: (address: string | null): Result<RoutePlan, RoutingError> => {
			if (address === "/bad") { return Result.err(RoutingError.InvalidParams); }
			const next = address === null ? "" : address as string;
			return Result.ok({ commit: (): void => write(next) });
		},
		address: (): Result<string | null, RoutingError> => {
			const value: string | null = read() === "" ? null : read();
			return Result.ok(value);
		},
		capture: (): string => read(),
		restore: (value: string): Result<RoutePlan, RoutingError> => {
			return Result.ok({ commit: (): void => write(value) });
		},
	};
}

test "arbitrary participants validate all regions before committing and clear omitted overlays" {
	let main = "/world";
	let inventory = "";
	const router = new RoutingRegistry("main");
	router.register(textParticipant(
		"main", (): string => main, (value: string): void => { main = value; },
	));
	router.register(textParticipant(
		"inventory", (): string => inventory, (value: string): void => { inventory = value; },
	));
	const invalid = router.apply("/world/2?__nav.inventory=%2Fbad");
	assert !invalid.ok;
	assert main === "/world" && inventory === "";
	const opened = router.apply("/world?__nav.inventory=%2Fitems%2F42");
	assert opened.ok;
	assert main === "/world" && inventory === "/items/42";
	const address = router.address();
	assert address.ok;
	if (address.ok) { assert address.value === "/world?__nav.inventory=%2Fitems%2F42"; }
	assert router.apply("/world").ok;
	assert inventory === "";
}

test "registration rejects duplicate scopes and unknown regions without changing state" {
	let main = "/first";
	const router = new RoutingRegistry("main");
	const participant = textParticipant(
		"main", (): string => main, (value: string): void => { main = value; },
	);
	const unregister = router.register(participant);
	let message = "";
	try { router.register(participant); } catch (error) { message = error.message; }
	assert message.indexOf("duplicate routing scope: main") >= 0, message;
	const unknown = router.apply("/second?__nav.unknown=%2Fx");
	assert !unknown.ok;
	assert main === "/first";
	unregister();
	unregister();
	const missing = router.apply("/second");
	assert !missing.ok;
}

test "snapshots are independent of URLs and restore through participant contracts" {
	let current = "/detail";
	let stack = "home,detail";
	const router = new RoutingRegistry("main");
	const participant = textParticipant(
		"main", (): string => current, (value: string): void => { current = value; },
	);
	participant.capture = (): string => stack;
	participant.restore = (value: string): Result<RoutePlan, RoutingError> => {
		return Result.ok({ commit: (): void => { stack = value; current = "/detail"; } });
	};
	router.register(participant);
	const snapshot = router.capture();
	assert snapshot.regions[0].state === "home,detail";
	assert router.apply("/other").ok;
	stack = "other";
	assert router.restore(snapshot).ok;
	assert stack === "home,detail" && current === "/detail";
	assert !router.restore({ regions: [] }).ok;
}

test "inactive route bindings have no address" {
	const binding = bindRoute<ItemParams>(
		itemRoute,
		(): ItemParams | null => null,
		(params: ItemParams): void => {},
	);
	const address = binding.address();
	assert address.ok;
	if (address.ok) { assert address.value === null; }
}
