import {
	RoutePlan,
	RoutingError,
	RoutingParticipant,
	RoutingRegistry,
} from "../../src/navigation/routing";
import {
	RoutingHistory,
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

test "an entry whose snapshot does not parse resolves from its address" {
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
	history.push({ url: "/second", state: "not json" });
	assert history.go(-1);
	assert active === "/first", active;
	assert history.go(1);
	assert active === "/second", active;
	assert errors === 0, errors.toString();
	if (connected.ok) { connected.value.dispose(); }
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

function deferredHistory(initial: RoutingHistoryEntry): { history: RoutingHistory; fire: () => void } {
	const inner = createMemoryRoutingHistory(initial);
	let deltas: int32[] = [];
	const history: RoutingHistory = {
		writable: true,
		read: inner.read,
		index: inner.index,
		push: inner.push,
		replace: inner.replace,
		go: (delta: int32): boolean => {
			if (inner.index() + delta < 0) { return false; }
			deltas.push(delta);
			return true;
		},
		listen: inner.listen,
	};
	const fire = (): void => {
		const due = deltas;
		deltas = [];
		for (const delta of due) { inner.go(delta); }
	};
	return { history, fire };
}

test "a navigation issued while a go is in flight writes after the go lands" {
	let active = "";
	let errors: int32 = 0;
	const registry = new RoutingRegistry("main");
	registry.register(participant(
		(): string => active, (value: string): void => { active = value; },
	));
	const deferred = deferredHistory({ url: "/a", state: "" });
	const connected = createRoutingSession(
		registry, deferred.history, (error: RoutingError): void => { errors += 1; },
	);
	assert connected.ok;
	if (!connected.ok) { return; }
	const session = connected.value;
	assert session.navigate("/b", false).ok;
	const order: string[] = [];
	assert session.go(-1, (): void => { order.push("landed:" + deferred.history.read().url); });
	assert session.navigate("/c", false).ok;
	assert active === "/c";
	order.push("navigated");
	deferred.fire();
	assert order.join(",") === "navigated,landed:/a", order.join(",");
	assert deferred.history.read().url === "/c", deferred.history.read().url;
	assert deferred.history.index() === 1, deferred.history.index().toString();
	assert session.canGoBack();
	assert errors === 0;
	session.dispose();
}

test "a go issued while another is in flight runs after it lands, in order" {
	const registry = new RoutingRegistry("main");
	let active = "";
	registry.register(participant(
		(): string => active, (value: string): void => { active = value; },
	));
	const deferred = deferredHistory({ url: "/a", state: "" });
	const connected = createRoutingSession(
		registry, deferred.history, (error: RoutingError): void => {},
	);
	assert connected.ok;
	if (!connected.ok) { return; }
	const session = connected.value;
	assert session.navigate("/b", false).ok;
	assert session.navigate("/c", false).ok;
	const landed: string[] = [];
	assert session.go(-1, (): void => { landed.push(deferred.history.read().url); });
	assert session.go(-1, (): void => { landed.push(deferred.history.read().url); });
	deferred.fire();
	assert landed.join(",") === "/b", landed.join(",");
	deferred.fire();
	assert landed.join(",") === "/b,/a", landed.join(",");
	assert deferred.history.read().url === "/a", deferred.history.read().url;
	session.dispose();
}
