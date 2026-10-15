import { Accessor, Signal } from "../../src/core/signal";
import { Dispose } from "../../src/core/types";
import { NavigationChild } from "../../src/navigation/children";
import { ChildStack, createChildStack } from "../../src/navigation/childStack";
import {
	RoutePlan,
	RoutingError,
	RoutingParticipant,
	RoutingRegistry,
	RoutingSnapshot,
} from "../../src/navigation/routing";
import {
	RoutingHistory,
	RoutingHistoryEntry,
	RoutingSession,
	createMemoryRoutingHistory,
	createRoutingSession,
} from "../../src/navigation/routingHistory";
import {
	WebKeySerializer,
	WebNavigationError,
	WebNavigationOwner,
	childStackWebNavigation,
	webNavigationNode,
} from "../../src/navigation/webNavigation";
import { createWebHistory } from "../../src/navigation/webHistory";

struct Screen {
	name: string;
	detail: string;
}

interface ScreenInstance {
	name: string;
	inner: ChildStack<string, string> | null;
	web: WebNavigationOwner | null;
}

interface Controls {
	query: Signal<string>;
	innerAllowed: boolean;
	asked: string;
}

interface Log {
	lines: string;
	errors: int32;
}

interface SideRegion {
	value: string;
}

interface Fixture {
	stack: ChildStack<Screen, ScreenInstance>;
	memory: RoutingHistory;
	session: RoutingSession;
	log: Log;
	controls: Controls;
	stop: Dispose;
}

function screen(name: string): Screen {
	return { name, detail: "" };
}

function screenKey(screen: Screen): string {
	return screen.name;
}

function screenSerializer(): WebKeySerializer<Screen> {
	return {
		encode: (screen: Screen): string => screen.name + "/" + screen.detail,
		decode: (text: string): Result<Screen, WebNavigationError> => {
			const at = text.indexOf("/");
			if (at < 0) { return Result.err(WebNavigationError.UndecodableKey); }
			return Result.ok({
				name: text.substring(0, at),
				detail: text.substring(at + 1, text.length),
			});
		},
	};
}

function prefixed(prefix: string): WebKeySerializer<string> {
	return {
		encode: (value: string): string => prefix + value,
		decode: (text: string): Result<string, WebNavigationError> => {
			if (!text.startsWith(prefix)) { return Result.err(WebNavigationError.UndecodableKey); }
			return Result.ok(text.substring(prefix.length, text.length));
		},
	};
}

function pageKey(name: string): string {
	return name;
}

function pageInstance(configuration: Accessor<string>, active: Accessor<boolean>): string {
	return configuration();
}

function instances(
	controls: Controls,
): (configuration: Accessor<Screen>, active: Accessor<boolean>) => ScreenInstance {
	return (configuration: Accessor<Screen>, active: Accessor<boolean>): ScreenInstance => {
		const name = configuration().name;
		if (name !== "inner") { return { name, inner: null, web: null }; }
		const inner = createChildStack<string, string>(["a", "b"], pageKey, pageInstance);
		const web = childStackWebNavigation<string, string>(inner, prefixed("inner:"), {
			pathMapper: (child: NavigationChild<string, string>): string | null => child.configuration(),
			onBeforeNavigate: (): boolean => {
				controls.asked += "inner;";
				return controls.innerAllowed;
			},
		});
		return { name, inner, web: { webNavigation: webNavigationNode<string>(web) } };
	};
}

function resolver(
	stack: ChildStack<Screen, ScreenInstance>,
): (address: string | null) => Result<RoutePlan, RoutingError> {
	return (address: string | null): Result<RoutePlan, RoutingError> => {
		if (address === null) { return Result.err(RoutingError.NoMatch); }
		const value = address as string;
		const queryAt = value.indexOf("?");
		const path = queryAt < 0 ? value : value.substring(0, queryAt);
		const name = path.substring(1, path.length);
		if (name.indexOf("/") >= 0) { return Result.err(RoutingError.NoMatch); }
		const screens: Screen[] = [screen("home")];
		if (name !== "" && name !== "home") { screens.push(screen(name)); }
		return Result.ok({ commit: (): void => {
			stack.navigate((current: Screen[]): Screen[] => screens);
		} });
	};
}

function sideParticipant(side: SideRegion): RoutingParticipant {
	return {
		scope: "side",
		prepare: (address: string | null): Result<RoutePlan, RoutingError> => {
			const value = address === null ? "" : address as string;
			return Result.ok({ commit: (): void => { side.value = value; } });
		},
		address: (): Result<string | null, RoutingError> => {
			const address: string | null = side.value === "" ? null : side.value;
			return Result.ok(address);
		},
		capture: (): string => side.value,
		restore: (state: string): Result<RoutePlan, RoutingError> => {
			return Result.ok({ commit: (): void => { side.value = state; } });
		},
	};
}

function recorded(memory: RoutingHistory, log: Log): RoutingHistory {
	return {
		writable: true,
		read: memory.read,
		index: memory.index,
		push: (entry: RoutingHistoryEntry): void => {
			log.lines += "push " + entry.url + ";";
			memory.push(entry);
		},
		replace: (entry: RoutingHistoryEntry): void => {
			log.lines += "replace " + entry.url + ";";
			memory.replace(entry);
		},
		go: (delta: int32): boolean => {
			log.lines += "go " + delta.toString() + ";";
			return memory.go(delta);
		},
		listen: memory.listen,
	};
}

function start(url: string, side: SideRegion | null): Fixture {
	const log: Log = { lines: "", errors: 0 };
	const controls: Controls = { query: new Signal<string>(""), innerAllowed: true, asked: "" };
	const stack = createChildStack<Screen, ScreenInstance>(
		[screen("home")], screenKey, instances(controls),
	);
	const node = webNavigationNode<Screen>(childStackWebNavigation<Screen, ScreenInstance>(
		stack,
		screenSerializer(),
		{
			pathMapper: (child: NavigationChild<Screen, ScreenInstance>): string | null => {
				return child.configuration().name;
			},
			parametersMapper: (
				child: NavigationChild<Screen, ScreenInstance>,
			): Map<string, string> | null => {
				const query = controls.query.get();
				if (query === "") { return null; }
				const parameters = new Map<string, string>();
				parameters.set("q", query);
				return parameters;
			},
			onBeforeNavigate: (): boolean => {
				controls.asked += "root;";
				return true;
			},
			childSelector: (
				child: NavigationChild<Screen, ScreenInstance>,
			): WebNavigationOwner | null => child.instance.web,
		},
	));
	const web = createWebHistory("main", node, resolver(stack));
	const registry = new RoutingRegistry("main");
	registry.register(web.participant);
	if (side !== null) { registry.register(sideParticipant(side as SideRegion)); }
	const memory = createMemoryRoutingHistory({ url, state: "" });
	const connected = createRoutingSession(
		registry,
		recorded(memory, log),
		(error: RoutingError): void => { log.errors += 1; },
	);
	if (!connected.ok) { throw new Error("web history test: the session does not connect"); }
	const session = connected.value;
	const stop = web.enable(session);
	log.lines = "";
	return { stack, memory, session, log, controls, stop };
}

function finish(fixture: Fixture): int32 {
	fixture.stop();
	fixture.session.dispose();
	return fixture.log.errors;
}

function take(log: Log): string {
	const lines = log.lines;
	log.lines = "";
	return lines;
}

function names(stack: ChildStack<Screen, ScreenInstance>): string {
	const out: string[] = [];
	for (const configuration of stack.configurations()) { out.push(configuration.name); }
	return out.join(",");
}

function innerNames(stack: ChildStack<Screen, ScreenInstance>): string {
	const items = stack.items();
	const inner = items[items.length - 1].instance.inner;
	if (inner === null) { return "-"; }
	return (inner as ChildStack<string, string>).configurations().join(",");
}

test "a pushed item whose child holds history pushes one entry per child entry" {
	const fixture = start("/home", null);
	assert fixture.memory.read().url === "/home", fixture.memory.read().url;
	fixture.stack.push(screen("inner"));
	const pushed = take(fixture.log);
	assert pushed === "push /inner/a;push /inner/b;", pushed;
	assert fixture.memory.index() === 2, fixture.memory.index().toString();
	assert fixture.memory.go(-1);
	assert names(fixture.stack) === "home,inner", names(fixture.stack);
	assert innerNames(fixture.stack) === "a", innerNames(fixture.stack);
	assert take(fixture.log) === "", "a traversal writes nothing";
	assert finish(fixture) === 0, "routing errors";
}

test "a pop goes back by every entry the popped items held" {
	const fixture = start("/home", null);
	fixture.stack.push(screen("inner"));
	fixture.stack.push(screen("detail"));
	const pushed = take(fixture.log);
	assert pushed === "push /inner/a;push /inner/b;push /detail;", pushed;
	fixture.stack.navigate((current: Screen[]): Screen[] => [screen("home")]);
	const popped = take(fixture.log);
	assert popped === "go -3;", popped;
	assert fixture.memory.index() === 0, fixture.memory.index().toString();
	assert fixture.memory.read().url === "/home", fixture.memory.read().url;
	assert finish(fixture) === 0, "routing errors";
}

test "a pop past the first browser entry goes back as far as it can and replaces" {
	const fixture = start("/inner", null);
	assert fixture.memory.read().url === "/inner/b", fixture.memory.read().url;
	assert innerNames(fixture.stack) === "a,b", innerNames(fixture.stack);
	fixture.stack.push(screen("detail"));
	assert take(fixture.log) === "push /detail;";
	fixture.stack.navigate((current: Screen[]): Screen[] => [screen("home")]);
	const popped = take(fixture.log);
	assert popped === "go -1;replace /home;", popped;
	assert fixture.memory.index() === 0, fixture.memory.index().toString();
	assert fixture.memory.read().url === "/home", fixture.memory.read().url;
	assert finish(fixture) === 0, "routing errors";
}

test "a change that neither pushes nor pops rewrites from the first entry" {
	const fixture = start("/home", null);
	fixture.stack.push(screen("detail"));
	assert take(fixture.log) === "push /detail;";
	fixture.stack.navigate((current: Screen[]): Screen[] => [screen("other"), screen("more")]);
	const rewritten = take(fixture.log);
	assert rewritten === "go -1;replace /other;push /more;", rewritten;
	assert fixture.memory.index() === 1, fixture.memory.index().toString();
	assert fixture.memory.go(-1);
	assert names(fixture.stack) === "other", names(fixture.stack);
	assert take(fixture.log) === "";
	assert finish(fixture) === 0, "routing errors";
}

test "the same keys under a new address replace the current entry" {
	const fixture = start("/home", null);
	fixture.stack.push(screen("detail"));
	assert take(fixture.log) === "push /detail;";
	fixture.controls.query.set("x y");
	const replaced = take(fixture.log);
	assert replaced === "replace /detail?q=x%20y;", replaced;
	assert fixture.memory.index() === 1, fixture.memory.index().toString();
	assert fixture.memory.read().url === "/detail?q=x%20y", fixture.memory.read().url;
	assert finish(fixture) === 0, "routing errors";
}

test "a traversal applies the stored keys level by level" {
	const fixture = start("/home", null);
	fixture.stack.push(screen("inner"));
	const items = fixture.stack.items();
	(items[items.length - 1].instance.inner as ChildStack<string, string>).push("c");
	const pushed = take(fixture.log);
	assert pushed === "push /inner/a;push /inner/b;push /inner/c;", pushed;
	assert fixture.memory.go(-2);
	assert innerNames(fixture.stack) === "a", innerNames(fixture.stack);
	assert fixture.memory.go(-1);
	assert names(fixture.stack) === "home", names(fixture.stack);
	assert fixture.memory.go(3);
	assert names(fixture.stack) === "home,inner", names(fixture.stack);
	assert innerNames(fixture.stack) === "a,b,c", innerNames(fixture.stack);
	assert take(fixture.log) === "", "a traversal writes nothing";
	fixture.stack.pop();
	const popped = take(fixture.log);
	assert popped === "go -3;", popped;
	assert finish(fixture) === 0, "routing errors";
}

test "a refusal down the active branch returns the browser to where it was" {
	const fixture = start("/home", null);
	fixture.stack.push(screen("inner"));
	take(fixture.log);
	fixture.controls.innerAllowed = false;
	assert fixture.memory.go(-2);
	const returned = take(fixture.log);
	assert returned === "go 2;", returned;
	assert fixture.memory.index() === 2, fixture.memory.index().toString();
	assert fixture.memory.read().url === "/inner/b", fixture.memory.read().url;
	assert names(fixture.stack) === "home,inner", names(fixture.stack);
	assert innerNames(fixture.stack) === "a,b", innerNames(fixture.stack);
	assert fixture.controls.asked === "inner;", fixture.controls.asked;
	fixture.controls.innerAllowed = true;
	fixture.controls.asked = "";
	assert fixture.memory.go(-1);
	assert fixture.controls.asked === "inner;root;", fixture.controls.asked;
	assert innerNames(fixture.stack) === "a", innerNames(fixture.stack);
	assert take(fixture.log) === "";
	assert finish(fixture) === 0, "routing errors";
}

test "an entry without state resolves from its address" {
	const fixture = start("/home", null);
	fixture.memory.push({ url: "/detail", state: "" });
	assert fixture.memory.go(-1);
	assert names(fixture.stack) === "home", names(fixture.stack);
	assert fixture.memory.go(1);
	assert names(fixture.stack) === "home,detail", names(fixture.stack);
	assert take(fixture.log) === "", "a resolved entry writes nothing";
	fixture.stack.pop();
	const popped = take(fixture.log);
	assert popped === "go -1;", popped;
	assert fixture.memory.read().url === "/home", fixture.memory.read().url;
	assert finish(fixture) === 0, "routing errors";
}

function storedWith(fixture: Fixture, from: string, to: string): string {
	const state = fixture.memory.read().state;
	if (!state.includes(from)) { throw new Error("web history test: no " + from + " in " + state); }
	return state.replace(from, to);
}

test "an entry whose stored keys do not decode resolves from its address" {
	const fixture = start("/home", null);
	fixture.stack.push(screen("detail"));
	const undecodable = storedWith(fixture, "detail/", "detail");
	fixture.memory.replace({ url: "/detail", state: undecodable });
	fixture.stack.pop();
	take(fixture.log);
	assert fixture.memory.go(1);
	assert names(fixture.stack) === "home,detail", names(fixture.stack);
	assert take(fixture.log) === "", "a resolved entry writes nothing";
	assert finish(fixture) === 0, "routing errors";
}

test "an entry whose nested stored keys do not decode resolves from its address" {
	const fixture = start("/home", null);
	fixture.stack.push(screen("inner"));
	const undecodable = storedWith(fixture, "inner:b", "outer:b");
	fixture.memory.replace({ url: "/detail", state: undecodable });
	assert fixture.memory.go(-2);
	assert names(fixture.stack) === "home", names(fixture.stack);
	take(fixture.log);
	assert fixture.memory.go(2);
	assert names(fixture.stack) === "home,detail", names(fixture.stack);
	assert take(fixture.log) === "", "a resolved entry writes nothing";
	assert finish(fixture) === 0, "routing errors";
}

test "an entry whose key tree is malformed resolves from its address, or is reported" {
	const fixture = start("/home", null);
	const malformed: RoutingSnapshot = {
		regions: [{ scope: "main", state: "{\"nodes\":[{\"key\":\"home/\",\"children\":2}]}" }],
	};
	fixture.memory.push({ url: "/detail", state: JSON.stringify(malformed) });
	assert fixture.memory.go(-1);
	assert fixture.memory.go(1);
	assert names(fixture.stack) === "home,detail", names(fixture.stack);
	assert fixture.log.errors === 0, fixture.log.errors.toString();
	fixture.memory.push({ url: "/no/match", state: JSON.stringify(malformed) });
	assert fixture.memory.go(-1);
	assert fixture.memory.go(1);
	assert fixture.log.errors === 1, fixture.log.errors.toString();
	assert names(fixture.stack) === "home,detail", names(fixture.stack);
	assert finish(fixture) === 1, "the unresolvable entry is the one routing error";
}

test "an entry the binding pushes keeps the other regions' parts" {
	const side: SideRegion = { value: "" };
	const fixture = start("/home?__nav.side=%2Fpanel", side);
	assert side.value === "/panel", side.value;
	fixture.stack.push(screen("detail"));
	const pushed = take(fixture.log);
	assert pushed === "push /detail?__nav.side=%2Fpanel;", pushed;
	side.value = "/moved";
	assert fixture.memory.go(-1);
	assert side.value === "/panel", side.value;
	assert names(fixture.stack) === "home", names(fixture.stack);
	assert finish(fixture) === 0, "routing errors";
}
