import {
	RoutePlan,
	RoutingError,
	RoutingParticipant,
	RoutingRegistry,
} from "../../src/navigation/routing";
import {
	RoutingHistoryEntry,
	createMemoryRoutingHistory,
	createRoutingSession,
	createRequestRoutingHistory,
} from "../../src/navigation/routingHistory";

function participant(read: () => string, write: (value: string) => void): RoutingParticipant {
	return {
		scope: "main",
		prepare: (address: string | null): Result<RoutePlan, RoutingError> => {
			if (address === null) { return Result.err(RoutingError.NoMatch); }
			const value = address as string;
			return Result.ok({ commit: (): void => write(value) });
		},
		address: (): Result<string | null, RoutingError> => {
			const value: string | null = read();
			return Result.ok(value);
		},
		capture: (): string => read(),
		restore: (value: string): Result<RoutePlan, RoutingError> => {
			return Result.ok({ commit: (): void => write(value) });
		},
	};
}

test "memory history pushes replaces traverses and truncates forward entries" {
	const history = createMemoryRoutingHistory({ url: "/first", state: "" });
	let calls: int32 = 0;
	const unsubscribe = history.listen((entry: RoutingHistoryEntry): void => { calls += 1; });
	history.push({ url: "/second", state: "second" });
	history.push({ url: "/third", state: "third" });
	assert history.go(-1);
	assert history.read().url === "/second";
	history.replace({ url: "/edited", state: "edited" });
	assert history.go(1);
	assert history.read().url === "/third";
	assert history.go(-1);
	history.push({ url: "/fork", state: "fork" });
	assert !history.go(1);
	assert history.read().url === "/fork";
	assert calls === 3;
	unsubscribe();
	unsubscribe();
	history.go(-1);
	assert calls === 3;
}

test "routing sessions initialize before mount and restore snapshots on back and forward" {
	let active = "";
	let errors: int32 = 0;
	const registry = new RoutingRegistry("main");
	registry.register(participant(
		(): string => active, (value: string): void => { active = value; },
	));
	const history = createMemoryRoutingHistory({ url: "/first", state: "" });
	const connected = createRoutingSession(
		registry, history, (error: RoutingError): void => { errors += 1; },
	);
	assert connected.ok;
	assert active === "/first";
	if (connected.ok) {
		const session = connected.value;
		assert session.navigate("/second", false).ok;
		assert active === "/second";
		assert history.go(-1);
		assert active === "/first";
		assert history.go(1);
		assert active === "/second";
		active = "/edited";
		assert session.sync(true).ok;
		assert history.read().url === "/edited";
		session.dispose();
		session.dispose();
		history.go(-1);
		assert active === "/edited";
	}
	assert errors === 0;
}

test "request histories isolate SSR requests and refuse client navigation" {
	let first = "";
	let second = "";
	const left = new RoutingRegistry("main");
	const right = new RoutingRegistry("main");
	left.register(participant((): string => first, (value: string): void => { first = value; }));
	right.register(participant((): string => second, (value: string): void => { second = value; }));
	const request = createRequestRoutingHistory("/left");
	const a = createRoutingSession(left, request, (error: RoutingError): void => {});
	const b = createRoutingSession(
		right, createRequestRoutingHistory("/right"), (error: RoutingError): void => {},
	);
	assert a.ok && b.ok;
	assert first === "/left" && second === "/right";
	if (a.ok) {
		let message = "";
		try { a.value.navigate("/other", false); } catch (error) { message = error.message; }
		assert message.indexOf("request history") >= 0, message;
		assert first === "/left";
		a.value.dispose();
	}
	if (b.ok) { b.value.dispose(); }
	assert request.read().url === "/left";
}
