import { Accessor, Signal, accessor } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { Cleanup, Dispose } from "../../src/core/types";
import { NavigationChild } from "../../src/navigation/children";
import { ChildStack, createChildStack } from "../../src/navigation/childStack";
import { ChildPages, Pages, createChildPages } from "../../src/navigation/childPages";
import {
	ChildPanels,
	ChildPanelsMode,
	createChildPanels,
} from "../../src/navigation/childPanels";
import {
	PanelsHistoryKey,
	WebHistoryItem,
	WebKeySerializer,
	WebNavigation,
	WebNavigationError,
	WebNavigationNode,
	WebNavigationOwner,
	childPagesWebNavigation,
	childPanelsWebNavigation,
	childStackWebNavigation,
	webNavigationNode,
} from "../../src/navigation/webNavigation";

struct Screen {
	name: string;
	detail: string;
}

interface ScreenInstance {
	name: string;
	pages: ChildPages<string, string> | null;
	web: WebNavigationOwner | null;
}

type Tabs = ChildPanels<string, string, string, string, string, string>;

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

function makePages(items: string[], selectedIndex: int32): ChildPages<string, string> {
	return createChildPages<string, string>({ items, selectedIndex }, pageKey, pageInstance);
}

function screenInstance(
	configuration: Accessor<Screen>,
	active: Accessor<boolean>,
): ScreenInstance {
	const name = configuration().name;
	if (name !== "tabs") { return { name, pages: null, web: null }; }
	const pages = makePages(["feed", "inbox"], 0);
	const web = childPagesWebNavigation<string, string>(pages, prefixed("page:"));
	return { name, pages, web: { webNavigation: webNavigationNode<Pages<string>>(web) } };
}

function makeStack(names: string[]): ChildStack<Screen, ScreenInstance> {
	const initial: Screen[] = [];
	for (const name of names) { initial.push(screen(name)); }
	return createChildStack<Screen, ScreenInstance>(initial, screenKey, screenInstance);
}

function makePanels(main: string, details: string | null, mode: ChildPanelsMode): Tabs {
	return createChildPanels<string, string, string, string, string, string>(
		{ main, details, extra: null, mode },
		pageKey,
		pageKey,
		pageKey,
		pageInstance,
		pageInstance,
		pageInstance,
	);
}

function names(stack: ChildStack<Screen, ScreenInstance>): string {
	let out = "";
	for (const child of stack.items()) {
		out += child.instance.name + (child.active() ? "*" : "") + ";";
	}
	return out;
}

function keys(node: WebNavigationNode): string {
	let out = "";
	for (const item of node.history()) {
		out += item.key + (item.path === "" ? "" : "@" + item.path) + ";";
	}
	return out;
}

function lastChild(node: WebNavigationNode): WebNavigationNode | null {
	const history = node.history();
	const child = history[history.length - 1].child;
	return child === null ? null : (child as WebNavigationOwner).webNavigation;
}

function fixedOwner(key: string): WebNavigationOwner {
	const navigation: WebNavigation<string> = {
		serializer: prefixed(""),
		history: accessor((): WebHistoryItem<string>[] => {
			return [{ key, path: key, parameters: new Map<string, string>(), child: null }];
		}),
		onBeforeNavigate: (): boolean => true,
		navigate: (history: string[]): void => {},
	};
	return { webNavigation: webNavigationNode<string>(navigation) };
}

function optional(value: string | null): string {
	return value === null ? "-" : value as string;
}

function described(key: PanelsHistoryKey<string, string, string>): string {
	return key.main + " " + optional(key.details) + " " + optional(key.extra);
}

function failure(run: () => void): string {
	try { run(); } catch (error) { return error.message; }
	return "";
}

const MODES: ChildPanelsMode[] = [
	ChildPanelsMode.Single,
	ChildPanelsMode.Dual,
	ChildPanelsMode.Triple,
];

test "a navigation erases to serialized keys and applies only a fully decoded traversal" {
	const entries = new Signal<string[]>(["a"]);
	let allowed = true;
	const navigation: WebNavigation<string> = {
		serializer: prefixed("k:"),
		history: accessor((): WebHistoryItem<string>[] => {
			const items: WebHistoryItem<string>[] = [];
			for (const key of entries.get()) {
				items.push({ key, path: key, parameters: new Map<string, string>(), child: null });
			}
			return items;
		}),
		onBeforeNavigate: (): boolean => allowed,
		navigate: (history: string[]): void => { entries.set(history); },
	};
	const node = webNavigationNode<string>(navigation);
	let runs: int32 = 0;
	const stop = createRoot((d: Dispose): Dispose => {
		createEffect<int32>(
			(prev: int32 | null): int32 => { node.history(); return 0; },
			(value: int32, prev: int32 | null): Cleanup | null => { runs += 1; return null; },
		);
		return d;
	});
	assert keys(node) === "k:a@a;", keys(node);
	assert node.navigate(["k:a", "k:b"]).ok;
	assert runs === 2, runs.toString();
	assert keys(node) === "k:a@a;k:b@b;", keys(node);
	const refused = node.navigate(["k:c", "c"]);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error === WebNavigationError.UndecodableKey; }
	assert keys(node) === "k:a@a;k:b@b;", "a refused traversal changes nothing: " + keys(node);
	assert node.onBeforeNavigate();
	allowed = false;
	assert !node.onBeforeNavigate();
	stop();
}

test "a stack publishes every entry with the last active and follows the model" {
	const stack = makeStack(["list", "detail"]);
	const web = childStackWebNavigation<Screen, ScreenInstance>(stack, screenSerializer(), {
		pathMapper: (child: NavigationChild<Screen, ScreenInstance>): string | null => {
			return child.configuration().name;
		},
		parametersMapper: (
			child: NavigationChild<Screen, ScreenInstance>,
		): Map<string, string> | null => {
			const detail = child.configuration().detail;
			if (detail === "") { return null; }
			const parameters = new Map<string, string>();
			parameters.set("id", detail);
			return parameters;
		},
	});
	const node = webNavigationNode<Screen>(web);
	let runs: int32 = 0;
	const stop = createRoot((d: Dispose): Dispose => {
		createEffect<int32>(
			(prev: int32 | null): int32 => { node.history(); return 0; },
			(value: int32, prev: int32 | null): Cleanup | null => { runs += 1; return null; },
		);
		return d;
	});
	assert keys(node) === "list/@list;detail/@detail;", keys(node);
	stack.push({ name: "edit", detail: "7" });
	assert runs === 2, runs.toString();
	assert keys(node) === "list/@list;detail/@detail;edit/7@edit;", keys(node);
	const typed = web.history();
	assert typed[2].key.name === "edit" && typed[2].key.detail === "7";
	assert typed[2].parameters.get("id") === "7";
	assert typed[0].parameters.size === 0 && typed[0].child === null;
	assert stack.pop();
	assert runs === 3, runs.toString();
	assert keys(node) === "list/@list;detail/@detail;", keys(node);
	stop();
	stack.dispose();
}

test "a stack without history publishes only the active child" {
	const stack = makeStack(["a", "b"]);
	const web = childStackWebNavigation<Screen, ScreenInstance>(stack, screenSerializer(), {
		enableHistory: false,
	});
	const node = webNavigationNode<Screen>(web);
	assert keys(node) === "b/;", keys(node);
	stack.push(screen("c"));
	assert keys(node) === "c/;", keys(node);
	web.navigate([screen("x")]);
	assert names(stack) === "x*;", names(stack);
	stack.dispose();
}

test "a stack applies a traversal of keys and keeps the kept instances" {
	const stack = makeStack(["a", "b", "c"]);
	const a = stack.items()[0].instance;
	const node = webNavigationNode<Screen>(
		childStackWebNavigation<Screen, ScreenInstance>(stack, screenSerializer()),
	);
	assert node.navigate(["a/", "b/"]).ok;
	assert names(stack) === "a;b*;", names(stack);
	assert stack.items()[0].instance === a, "a kept entry keeps its instance";
	assert node.navigate(["a/", "b/", "c/9"]).ok;
	assert names(stack) === "a;b;c*;", names(stack);
	assert stack.configurations()[2].detail === "9";
	assert keys(node) === "a/;b/;c/9;", keys(node);
	stack.dispose();
}

test "an undecodable key is refused and the model stays as it was" {
	const stack = makeStack(["a", "b", "c"]);
	const node = webNavigationNode<Screen>(
		childStackWebNavigation<Screen, ScreenInstance>(stack, screenSerializer()),
	);
	const refused = node.navigate(["a/", "broken"]);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error === WebNavigationError.UndecodableKey; }
	assert names(stack) === "a;b;c*;", names(stack);
	stack.dispose();
}

test "pages publish one entry for the selected page" {
	const pages = makePages(["home", "search", "profile"], 0);
	const search = fixedOwner("results");
	const web = childPagesWebNavigation<string, string>(pages, prefixed("page:"), {
		pathMapper: (page: NavigationChild<string, string>): string | null => page.instance,
		childSelector: (child: NavigationChild<string, string>): WebNavigationOwner | null => {
			return child.instance === "search" ? search : null;
		},
	});
	let history = web.history();
	assert history.length === 1, history.length.toString();
	assert history[0].key.selectedIndex === 0 && history[0].key.items.length === 3;
	assert history[0].key.items[1] === "search";
	assert history[0].path === "home" && history[0].child === null;
	pages.select(1);
	history = web.history();
	assert history.length === 1 && history[0].key.selectedIndex === 1;
	assert history[0].path === "search" && history[0].child === search;
	pages.dispose();
}

test "pages publish the visited pages before the selected one, each with its own part and child" {
	const pages = makePages(["home", "search", "profile"], 0);
	const search = fixedOwner("results");
	const web = childPagesWebNavigation<string, string>(pages, prefixed("page:"), {
		pathMapper: (page: NavigationChild<string, string>): string | null => page.instance,
		childSelector: (child: NavigationChild<string, string>): WebNavigationOwner | null => {
			return child.instance === "search" ? search : null;
		},
		visited: (current: ChildPages<string, string>): int32[] => {
			const at = current.selectedIndex();
			return at === 0 ? [at] : [1, at];
		},
	});
	const node = webNavigationNode<Pages<string>>(web);
	assert web.history().length === 1, web.history().length.toString();
	pages.select(2);
	const history = web.history();
	assert history.length === 2, history.length.toString();
	assert history[0].key.selectedIndex === 1 && history[0].path === "search" && history[0].child === search;
	assert history[1].key.selectedIndex === 2 && history[1].path === "profile" && history[1].child === null;
	const keys = [node.history()[0].key];
	assert node.navigate(keys).ok;
	assert pages.selectedIndex() === 1, pages.selectedIndex().toString();
	pages.dispose();
}

test "pages refuse visited pages that do not end with the selected one" {
	const pages = makePages(["home", "search"], 1);
	const web = childPagesWebNavigation<string, string>(pages, prefixed("page:"), {
		visited: (current: ChildPages<string, string>): int32[] => [0],
	});
	let message = "";
	try { web.history(); } catch (error) { message = error.message; }
	assert message === "child pages web navigation: the visited pages do not end with the selected one", message;
	pages.dispose();
}

test "pages round-trip their key and refuse one that does not decode" {
	const pages = makePages(["home", "search", "profile"], 0);
	const web = childPagesWebNavigation<string, string>(pages, prefixed("page:"));
	const node = webNavigationNode<Pages<string>>(web);
	pages.select(1);
	const key = node.history()[0].key;
	pages.select(2);
	assert node.navigate([key]).ok;
	assert pages.selectedIndex() === 1, pages.selectedIndex().toString();
	const decoded = web.serializer.decode(key);
	assert decoded.ok;
	if (decoded.ok) { assert decoded.value.items[2] === "profile"; }
	const refused = [
		"{",
		"{\"items\":[\"home\"],\"selectedIndex\":0}",
		"{\"items\":[\"page:home\"],\"selectedIndex\":5}",
	];
	for (const bad of refused) {
		assert !node.navigate([bad]).ok, bad;
		assert pages.selectedIndex() === 1, bad;
	}
	web.navigate([{ items: ["a", "b"], selectedIndex: 1 }]);
	assert pages.pages().items.length === 2 && pages.selectedIndex() === 1;
	pages.dispose();
}

test "panels publish one entry of main, details and extra in every mode" {
	for (const mode of MODES) {
		const panels = makePanels("list", "item", mode);
		const owner = fixedOwner("nested");
		const web = childPanelsWebNavigation<string, string, string, string, string, string>(
			panels,
			prefixed("m:"),
			prefixed("d:"),
			prefixed("e:"),
			{
				pathMapper: (current: Tabs): string | null => current.mode().toString(),
				childSelector: (current: Tabs): WebNavigationOwner | null => {
					return current.details() === null ? null : owner;
				},
			},
		);
		let history = web.history();
		assert history.length === 1, history.length.toString();
		assert described(history[0].key) === "list item -", described(history[0].key);
		assert history[0].path === mode.toString(), history[0].path;
		assert history[0].child === owner;
		const other = mode === ChildPanelsMode.Single
			? ChildPanelsMode.Triple
			: ChildPanelsMode.Single;
		panels.setMode(other);
		history = web.history();
		assert described(history[0].key) === "list item -", "the mode is not part of the key";
		assert history[0].path === other.toString(), history[0].path;
		web.navigate([{ main: "home", details: null, extra: "help" }]);
		const applied = panels.panels();
		assert applied.main === "home" && applied.details === null && applied.extra === "help";
		assert applied.mode === other, "navigate keeps the mode";
		assert web.history()[0].child === null;
		panels.dispose();
	}
}

test "panels round-trip their key and refuse one that does not decode" {
	const panels = makePanels("list", "item", ChildPanelsMode.Dual);
	const web = childPanelsWebNavigation<string, string, string, string, string, string>(
		panels,
		prefixed("m:"),
		prefixed("d:"),
		prefixed("e:"),
		{},
	);
	const node = webNavigationNode<PanelsHistoryKey<string, string, string>>(web);
	const key = node.history()[0].key;
	panels.navigateTo("home", null, "help");
	assert node.navigate([key]).ok;
	assert described(web.history()[0].key) === "list item -", described(web.history()[0].key);
	for (const bad of ["{}", "x", "{\"main\":\"list\",\"hasDetails\":false,\"details\":\"\"}"]) {
		assert !node.navigate([bad]).ok, bad;
		assert described(web.history()[0].key) === "list item -", bad;
	}
	const many = failure((): void => {
		web.navigate([
			{ main: "a", details: null, extra: null },
			{ main: "b", details: null, extra: null },
		]);
	});
	assert many === "child panels web navigation: a history of 2 items, expected 1", many;
	panels.dispose();
}

test "the active entry's owner reaches the nested history" {
	const stack = makeStack(["home", "tabs"]);
	const node = webNavigationNode<Screen>(
		childStackWebNavigation<Screen, ScreenInstance>(stack, screenSerializer(), {
			childSelector: (
				child: NavigationChild<Screen, ScreenInstance>,
			): WebNavigationOwner | null => child.instance.web,
		}),
	);
	assert node.history()[0].child === null;
	const nested = lastChild(node);
	assert nested !== null;
	const tabs = stack.active().instance.pages as ChildPages<string, string>;
	const before = (nested as WebNavigationNode).history()[0].key;
	tabs.select(1);
	const after = (lastChild(node) as WebNavigationNode).history()[0].key;
	assert before !== after, after;
	tabs.select(0);
	assert (lastChild(node) as WebNavigationNode).navigate([after]).ok;
	assert tabs.selectedIndex() === 1, tabs.selectedIndex().toString();
	stack.dispose();
}

test "onBeforeNavigate is passed through and allows by default" {
	let allowed = false;
	const stack = makeStack(["a"]);
	const web = childStackWebNavigation<Screen, ScreenInstance>(stack, screenSerializer(), {
		onBeforeNavigate: (): boolean => allowed,
	});
	const node = webNavigationNode<Screen>(web);
	assert !web.onBeforeNavigate() && !node.onBeforeNavigate();
	allowed = true;
	assert web.onBeforeNavigate() && node.onBeforeNavigate();
	const pages = makePages(["home"], 0);
	assert childPagesWebNavigation<string, string>(pages, prefixed("p:")).onBeforeNavigate();
	const panels = makePanels("list", null, ChildPanelsMode.Single);
	assert childPanelsWebNavigation<string, string, string, string, string, string>(
		panels,
		prefixed("m:"),
		prefixed("d:"),
		prefixed("e:"),
	).onBeforeNavigate();
	const refusing = childPanelsWebNavigation<string, string, string, string, string, string>(
		panels,
		prefixed("m:"),
		prefixed("d:"),
		prefixed("e:"),
		{ onBeforeNavigate: (): boolean => false },
	);
	const refusingNode = webNavigationNode<PanelsHistoryKey<string, string, string>>(refusing);
	assert !refusingNode.onBeforeNavigate();
	panels.dispose();
	pages.dispose();
	stack.dispose();
}
