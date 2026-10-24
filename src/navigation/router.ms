import { Accessor, Signal, accessor, untrack } from "../core/signal";
import { flush } from "../core/runtime";
import { Dispose } from "../core/types";
import { mapArray } from "../core/array";
import { Host, HostNode, NeonNode } from "../render/hostTypes";
import { createComponent } from "../render/component";
import { createContext, useContext } from "../render/context";
import { View } from "../components/primitives";
import {
	RoutePlan,
	RoutingError,
	RoutingParticipant,
	RoutingRegistry,
	decodeRouteComponent,
	encodeRouteComponent,
} from "./routing";
import { RoutingHistory, RoutingSession, createRoutingSession } from "./routingHistory";
import {
	GuardDecision,
	MatchedRoute,
	RouteDef,
	RouteEntry,
	RouteMatch,
	RouteNode,
	RouteTree,
	PreloadArgs,
	PreloadIntent,
	RouterLocation,
	createRouteTree,
	hrefOf,
	path,
} from "./route";
import { PathMatch, createMatcher, expandOptionals, normalizePath } from "./routeMatcher";
import { NavigationChild } from "./children";
import { ChildStack, createChildStack } from "./childStack";
import { BackBehavior, ChildPages, Pages, createChildPages } from "./childPages";
import {
	WebKeySerializer,
	WebNavigationError,
	WebNavigationOwner,
	childPagesWebNavigation,
	childStackWebNavigation,
	webNavigationNode,
} from "./webNavigation";
import { WebHistory, createWebHistory } from "./webHistory";
import { StackPresentation, renderPages, renderStack, renderStackTop } from "./childView";
import { ScreenOptions } from "./core";
import { TabBar, TabList, TabTrigger, TabsContext } from "./tabBar";

const MAX_REDIRECTS: int32 = 20;
const PERMANENT_REDIRECT: int32 = 308;

export interface LayoutProps {
	children: NeonNode;
}

export enum RouteNavigator {
	Stack,
	Tabs,
}

export const Stack: RouteNavigator = RouteNavigator.Stack;
export const Tabs: RouteNavigator = RouteNavigator.Tabs;

export interface RouteRef {
	node: RouteNode;
}

export interface RouteConfig {
	path?: string | null;
	route?: RouteRef | null;
	component?: (() => NeonNode) | null;
	layout?: ((props: LayoutProps) => NeonNode) | null;
	navigator?: RouteNavigator | null;
	initial?: string | null;
	backBehavior?: BackBehavior | null;
	presentation?: StackPresentation | null;
	resolveOnReload?: boolean | null;
	options?: ScreenOptions | (() => ScreenOptions) | null;
	status?: int32 | null;
	guard?: ((params: Map<string, string>, found: RouteMatch) => GuardDecision) | null;
	paths?: (() => Map<string, string>[]) | null;
	preload?: ((args: PreloadArgs<Map<string, string>>) => void) | null;
	children?: RouteConfig[] | null;
}

export interface RouteView {
	node: RouteNode;
	component: (() => NeonNode) | null;
	layout: ((props: LayoutProps) => NeonNode) | null;
	navigator: RouteNavigator | null;
	initial: int32;
	backBehavior: BackBehavior;
	presentation: StackPresentation;
	resolveOnReload: boolean;
	options: ScreenOptions | (() => ScreenOptions) | null;
	children: int32[];
	label: string;
}

export interface Routes {
	tree: RouteTree;
	views: RouteView[];
	roots: int32[];
}

function patternOf(config: RouteConfig): string | null {
	const typed = config.route;
	return typed === null ? config.path : (typed as RouteRef).node.pattern;
}

function labelOf(config: RouteConfig): string {
	const pattern = patternOf(config);
	return pattern === null ? "a route without a path" : "\"" + (pattern as string) + "\"";
}

function takesParams(pattern: string | null): boolean {
	if (pattern === null) { return false; }
	return (pattern as string).indexOf(":") >= 0 || (pattern as string).indexOf("*") >= 0;
}

function initialOf(config: RouteConfig, children: RouteConfig[], ids: int32[]): int32 {
	const initial = config.initial;
	if (initial === null) { return -1; }
	const wanted = initial as string;
	if (config.navigator === null || config.navigator as RouteNavigator !== RouteNavigator.Stack) {
		throw new Error("routing: " + labelOf(config) + " names an initial route, which only a Stack takes");
	}
	for (let i = 0; i < children.length; i += 1) {
		if ((patternOf(children[i]) ?? "") !== wanted) { continue; }
		if (takesParams(patternOf(children[i]))) {
			throw new Error(
				"routing: the initial route \"" + wanted + "\" of " + labelOf(config) + " takes params",
			);
		}
		return ids[i];
	}
	throw new Error("routing: " + labelOf(config) + " has no child \"" + wanted + "\" to start on");
}

function backBehaviorOf(config: RouteConfig): BackBehavior {
	const behavior = config.backBehavior;
	if (behavior === null) { return "firstRoute"; }
	if (config.navigator === null || config.navigator as RouteNavigator !== RouteNavigator.Tabs) {
		throw new Error("routing: " + labelOf(config) + " names a backBehavior, which only Tabs take");
	}
	if (behavior as BackBehavior === "initialRoute") {
		throw new Error("routing: " + labelOf(config) + " goes back to its initial route, which Tabs do not take");
	}
	return behavior as BackBehavior;
}

function presentationOf(config: RouteConfig, stacked: boolean): StackPresentation {
	const presentation = config.presentation;
	if (presentation === null) { return "card"; }
	if (!stacked) {
		throw new Error("routing: " + labelOf(config) + " names a presentation, which only a route in a Stack takes");
	}
	return presentation as StackPresentation;
}

function optionsOf(config: RouteConfig, tabbed: boolean): ScreenOptions | (() => ScreenOptions) | null {
	const options = config.options;
	if (options !== null && !tabbed) {
		throw new Error("routing: " + labelOf(config) + " names options, which only a route in Tabs reads");
	}
	return options;
}

function readOptions(options: ScreenOptions | (() => ScreenOptions) | null): ScreenOptions {
	if (options === null) { return {}; }
	if (typeof options === "function") { return (options as () => ScreenOptions)(); }
	return options as ScreenOptions;
}

function within(parent: RouteNavigator | null, navigator: RouteNavigator): boolean {
	return parent !== null && parent as RouteNavigator === navigator;
}

function compile(configs: RouteConfig[], views: RouteView[], ids: int32[], parent: RouteNavigator | null): RouteEntry[] {
	const entries: RouteEntry[] = [];
	for (const config of configs) {
		const children = config.children ?? [];
		const leaf = children.length === 0;
		if (leaf && config.layout !== null) {
			throw new Error("routing: " + labelOf(config) + " has a layout but no children to lay out");
		}
		if (leaf && config.navigator !== null) {
			throw new Error("routing: " + labelOf(config) + " has a navigator but no children to navigate");
		}
		if (leaf && config.component === null) {
			throw new Error("routing: " + labelOf(config) + " has neither children nor a component");
		}
		if (!leaf && config.component !== null) {
			throw new Error("routing: " + labelOf(config) + " has children, so it takes a layout, not a component");
		}
		const typed = config.route;
		if (typed !== null && (config.path !== null || config.status !== null || config.guard !== null || config.paths !== null || config.preload !== null)) {
			throw new Error("routing: " + labelOf(config) + " takes its path, status, guard, paths and preload from its route");
		}
		const node = typed === null
			? path(config.path, { status: config.status, guard: config.guard, paths: config.paths, preload: config.preload }).node
			: (typed as RouteRef).node;
		const id = views.length as int32;
		const view: RouteView = {
			node,
			component: config.component,
			layout: config.layout,
			navigator: config.navigator,
			initial: -1,
			backBehavior: backBehaviorOf(config),
			presentation: presentationOf(config, within(parent, RouteNavigator.Stack)),
			resolveOnReload: config.resolveOnReload ?? false,
			options: optionsOf(config, within(parent, RouteNavigator.Tabs)),
			children: [],
			label: labelOf(config),
		};
		views.push(view);
		ids.push(id);
		const childIds: int32[] = [];
		entries.push({ node, children: leaf ? null : compile(children, views, childIds, config.navigator) });
		view.children = childIds;
		view.initial = initialOf(config, children, childIds);
	}
	return entries;
}

export function createRoutes(configs: RouteConfig[]): Routes {
	const views: RouteView[] = [];
	const roots: int32[] = [];
	const entries = compile(configs, views, roots, null);
	return { tree: createRouteTree(entries), views, roots };
}

export { RouterLocation, PreloadArgs, PreloadIntent } from "./route";

export interface RouterResponse {
	status: int32;
	location: string | null;
}

export interface NavigateOptions {
	replace?: boolean | null;
}

export interface ToOptions<P> {
	to: RouteDef<P>;
	params: P;
	search?: Map<string, string> | null;
	replace?: boolean | null;
}

interface Resolved {
	address: string;
	match: RouteMatch;
	status: int32;
	redirect: int32;
}

function pathnameOf(address: string): string {
	let end = address.length;
	const query = address.indexOf("?");
	const hash = address.indexOf("#");
	if (query >= 0) { end = query; }
	if (hash >= 0 && hash < end) { end = hash; }
	return address.substring(0, end);
}

function withoutTrailingSlash(address: string): string | null {
	const pathname = pathnameOf(address);
	let end = pathname.length;
	while (end > 1 && pathname[end - 1] === "/") { end -= 1; }
	if (end === pathname.length) { return null; }
	return pathname.substring(0, end) + address.substring(pathname.length, address.length);
}

function follow(tree: RouteTree, address: string): Result<Resolved, RoutingError> {
	let at = address;
	let first: int32 = 0;
	for (let hop: int32 = 0; hop <= MAX_REDIRECTS; hop += 1) {
		const trimmed = withoutTrailingSlash(at);
		if (trimmed !== null) {
			if (first === 0) { first = PERMANENT_REDIRECT; }
			at = trimmed as string;
			continue;
		}
		const resolved = try tree.resolve(at);
		const next = resolved.redirect;
		if (next === null) {
			return Result.ok({ address: at, match: resolved.match, status: resolved.status, redirect: first });
		}
		if (first === 0) { first = resolved.status; }
		at = next as string;
	}
	throw new Error(
		"routing: more than " + MAX_REDIRECTS.toString() + " redirects from \"" + address + "\"",
	);
}

enum LevelKind {
	Slot,
	Stack,
	Tabs,
}

interface Stop {
	route: int32;
	visit: int32;
	seed: string;
	path: string;
	part: string;
	params: Map<string, string>;
	search: Map<string, string>;
	hash: string;
	intent: PreloadIntent;
}

struct StopKey {
	route: int32;
	visit: int32;
	seed: string;
}

interface Seeding {
	cold: boolean;
}

interface Place {
	level: Level | null;
}

interface Level {
	kind: LevelKind;
	stack: ChildStack<Stop, Place> | null;
	pages: ChildPages<Stop, Place> | null;
	visit: (at: int32) => void;
	owner: WebNavigationOwner;
	dispose: Dispose;
}

function stopKey(stop: Stop): string {
	return stop.route.toString() + "|" + stop.path + "|" + stop.visit.toString();
}

function trimSlashes(text: string): string {
	let trimmed = text;
	while (trimmed.startsWith("/")) { trimmed = trimmed.substring(1, trimmed.length); }
	while (trimmed.endsWith("/")) { trimmed = trimmed.substring(0, trimmed.length - 1); }
	return trimmed;
}

function partOf(full: string, parent: string): string {
	const base = parent === "/" ? "" : parent;
	return trimSlashes(full.startsWith(base) ? full.substring(base.length, full.length) : full);
}

function idOf(routes: Routes, node: RouteNode): int32 {
	for (let i = 0; i < routes.views.length; i += 1) {
		if (routes.views[i].node === node) { return i as int32; }
	}
	throw new Error("routing: a matched route has no view in its route tree");
}

function leafView(routes: Routes, stop: Stop): boolean {
	return routes.views[stop.route].children.length === 0;
}

function stopOf(
	routes: Routes,
	chain: MatchedRoute[],
	depth: int32,
	search: Map<string, string>,
	hash: string,
	seed: string,
	visit: int32,
	intent: PreloadIntent,
): Stop {
	const matched = chain[depth];
	const parent = depth === 0 ? "" : chain[depth - 1].path;
	const full = depth === chain.length - 1 ? seed : matched.path;
	return {
		route: idOf(routes, matched.node),
		visit,
		seed,
		path: full,
		part: partOf(full, parent),
		params: matched.params,
		search,
		hash,
		intent,
	};
}

function defaultStop(routes: Routes, id: int32, parent: string, intent: PreloadIntent): Stop {
	const view = routes.views[id];
	const none = new Map<string, string>();
	const built = routes.tree.href(view.node, none, none);
	if (!built.ok) {
		throw new Error("routing: " + view.label + " takes params, so it cannot open by default");
	}
	const address = built.value;
	return {
		route: id,
		visit: 0,
		seed: address,
		path: address,
		part: partOf(address, parent),
		params: none,
		search: none,
		hash: "",
		intent,
	};
}

function childrenOf(routes: Routes, owner: int32): int32[] {
	return owner < 0 ? routes.roots : routes.views[owner].children;
}

function kindOf(routes: Routes, owner: int32): LevelKind {
	if (owner < 0) { return LevelKind.Slot; }
	const navigator = routes.views[owner].navigator;
	if (navigator === null) { return LevelKind.Slot; }
	return match (navigator as RouteNavigator) {
		RouteNavigator.Stack => LevelKind.Stack,
		RouteNavigator.Tabs => LevelKind.Tabs,
	};
}

function defaultChild(routes: Routes, owner: int32): int32 {
	if (owner >= 0 && routes.views[owner].initial >= 0) { return routes.views[owner].initial; }
	const none = new Map<string, string>();
	for (const id of childrenOf(routes, owner)) {
		if (routes.tree.href(routes.views[id].node, none, none).ok) { return id; }
	}
	const label = owner < 0 ? "the route tree" : routes.views[owner].label;
	throw new Error("routing: " + label + " has no route that opens without params");
}

function stopSerializer(routes: Routes): WebKeySerializer<Stop> {
	return {
		encode: (stop: Stop): string => {
			const key: StopKey = { route: stop.route, visit: stop.visit, seed: stop.seed };
			return JSON.stringify(key);
		},
		decode: (text: string): Result<Stop, WebNavigationError> => {
			const parsed = JSON.parse<StopKey>(text);
			if (!parsed.ok) { return Result.err(WebNavigationError.UndecodableKey); }
			const key = parsed.value;
			if (key.route < 0 || key.route >= routes.views.length || key.visit < 0) {
				return Result.err(WebNavigationError.UndecodableKey);
			}
			const node = routes.views[key.route].node;
			const found = routes.tree.match(key.seed, node);
			if (!found.ok) { return Result.err(WebNavigationError.UndecodableKey); }
			const chain = found.value.chain;
			for (let depth: int32 = 0; depth < chain.length; depth += 1) {
				if (chain[depth].node !== node) { continue; }
				const none = new Map<string, string>();
				return Result.ok(stopOf(routes, chain, depth, none, "", key.seed, key.visit, "native"));
			}
			return Result.err(WebNavigationError.UndecodableKey);
		},
	};
}

function placeOf(routes: Routes, stop: Stop, seeding: Seeding): Place {
	const view = routes.views[stop.route];
	if (view.children.length === 0) { return { level: null }; }
	const found = routes.tree.match(stop.seed, view.node);
	if (found.ok) {
		const chain = found.value.chain;
		for (let depth: int32 = 0; depth + 1 < chain.length; depth += 1) {
			if (chain[depth].node === view.node && chain[depth].path === stop.path) {
				return { level: createLevel(routes, stop.route, stop.path, chain, depth + 1, stop, seeding) };
			}
		}
	}
	return { level: createLevel(routes, stop.route, stop.path, null, 0, stop, seeding) };
}

function seedStops(
	routes: Routes,
	owner: int32,
	parent: string,
	chain: MatchedRoute[] | null,
	depth: int32,
	from: Stop,
	seeding: Seeding,
): Stop[] {
	if (chain === null) { return [defaultStop(routes, defaultChild(routes, owner), parent, from.intent)]; }
	const matched = chain as MatchedRoute[];
	const leaf = depth === matched.length - 1;
	const seed = leaf ? pathnameOf(from.seed) : from.seed;
	const target = stopOf(routes, matched, depth, from.search, from.hash, seed, 0, from.intent);
	const initial = owner < 0 || !seeding.cold ? -1 : routes.views[owner].initial;
	if (initial < 0 || initial === target.route) { return [target]; }
	return [defaultStop(routes, initial, parent, from.intent), target];
}

function createLevel(
	routes: Routes,
	owner: int32,
	parent: string,
	chain: MatchedRoute[] | null,
	depth: int32,
	from: Stop,
	seeding: Seeding,
): Level {
	const kind = kindOf(routes, owner);
	const serializer = stopSerializer(routes);
	const factory = (configuration: Accessor<Stop>, active: Accessor<boolean>): Place => {
		return placeOf(routes, configuration(), seeding);
	};
	const nested = (place: Place): WebNavigationOwner | null => {
		const level = place.level;
		return level === null ? null : (level as Level).owner;
	};
	if (kind === LevelKind.Tabs) {
		const items: Stop[] = [];
		let selectedIndex: int32 = 0;
		const children = childrenOf(routes, owner);
		for (let i = 0; i < children.length; i += 1) {
			const id = children[i];
			if (chain !== null && idOf(routes, (chain as MatchedRoute[])[depth].node) === id) {
				items.push(seedStops(routes, owner, parent, chain, depth, from, seeding)[0]);
				selectedIndex = i as int32;
			} else {
				items.push(defaultStop(routes, id, parent, from.intent));
			}
		}
		const pages = createChildPages<Stop, Place>({ items, selectedIndex }, stopKey, factory);
		const behavior = routes.views[owner].backBehavior;
		let visits: int32[] = [selectedIndex];
		const visit = (at: int32): void => {
			const kept: int32[] = [];
			for (const seen of visits) {
				if (seen !== at) { kept.push(seen); }
			}
			kept.push(at);
			visits = kept;
		};
		const web = childPagesWebNavigation<Stop, Place>(pages, serializer, {
			pathMapper: (page: NavigationChild<Stop, Place>): string | null => page.configuration().part,
			parametersMapper: (page: NavigationChild<Stop, Place>): Map<string, string> | null => {
				const stop = page.configuration();
				return leafView(routes, stop) ? stop.search : null;
			},
			childSelector: (child: NavigationChild<Stop, Place>): WebNavigationOwner | null => {
				return nested(child.instance);
			},
			visited: (current: ChildPages<Stop, Place>): int32[] => {
				const at = current.selectedIndex();
				if (behavior === "history") { return visits; }
				return behavior === "none" || at === 0 ? [at] : [0, at];
			},
		});
		const node = webNavigationNode<Pages<Stop>>({
			serializer: web.serializer,
			history: web.history,
			onBeforeNavigate: web.onBeforeNavigate,
			navigate: (keys: Pages<Stop>[]): void => {
				const restored: int32[] = [];
				for (const key of keys) {
					if (key.selectedIndex >= 0) { restored.push(key.selectedIndex); }
				}
				visits = restored;
				web.navigate(keys);
			},
		});
		return {
			kind,
			stack: null,
			pages,
			visit,
			owner: { webNavigation: node },
			dispose: (): void => pages.dispose(),
		};
	}
	const stack = createChildStack<Stop, Place>(
		seedStops(routes, owner, parent, chain, depth, from, seeding),
		stopKey,
		factory,
	);
	const web = childStackWebNavigation<Stop, Place>(stack, serializer, {
		pathMapper: (child: NavigationChild<Stop, Place>): string | null => child.configuration().part,
		parametersMapper: (child: NavigationChild<Stop, Place>): Map<string, string> | null => {
			const stop = child.configuration();
			return leafView(routes, stop) ? stop.search : null;
		},
		childSelector: (child: NavigationChild<Stop, Place>): WebNavigationOwner | null => {
			return nested(child.instance);
		},
	});
	return {
		kind,
		stack,
		pages: null,
		visit: (at: int32): void => {},
		owner: { webNavigation: webNavigationNode<Stop>(web) },
		dispose: (): void => stack.dispose(),
	};
}

function activeChild(level: Level): NavigationChild<Stop, Place> {
	if (level.kind === LevelKind.Tabs) {
		const selected = (level.pages as ChildPages<Stop, Place>).selected();
		if (selected === null) { throw new Error("routing: a tab level has no selected page"); }
		return selected as NavigationChild<Stop, Place>;
	}
	return (level.stack as ChildStack<Stop, Place>).active();
}

function freeVisit(stops: Stop[], route: int32, path: string, skip: int32): int32 {
	let visit: int32 = 0;
	let taken = true;
	while (taken) {
		taken = false;
		for (let i = 0; i < stops.length; i += 1) {
			const stop = stops[i];
			if (i !== skip && stop.route === route && stop.path === path && stop.visit === visit) {
				taken = true;
			}
		}
		if (taken) { visit += 1; }
	}
	return visit;
}

function sameSearch(a: Map<string, string>, b: Map<string, string>): boolean {
	if (a.size !== b.size) { return false; }
	for (const name of a) {
		if (!b.has(name) || b.get(name) !== a.get(name)) { return false; }
	}
	return true;
}

enum Walked {
	Changed,
	HashOnly,
	Unchanged,
}

interface Target {
	chain: MatchedRoute[];
	search: Map<string, string>;
	hash: string;
	seed: string;
	replace: boolean;
	intent: PreloadIntent;
}

function updated(stop: Stop, target: Target): Stop {
	return { ...stop, search: target.search, hash: target.hash };
}

function walkLeaf(stop: Stop, target: Target, write: (next: Stop) => void): Walked {
	if (stop.hash === target.hash && sameSearch(stop.search, target.search)) { return Walked.Unchanged; }
	const hashOnly = sameSearch(stop.search, target.search);
	write(updated(stop, target));
	return hashOnly ? Walked.HashOnly : Walked.Changed;
}

function walk(routes: Routes, level: Level, target: Target, depth: int32): Walked {
	const chain = target.chain;
	const route = idOf(routes, chain[depth].node);
	const leaf = depth === chain.length - 1;
	const seed = target.seed;
	const routePath = leaf ? seed : chain[depth].path;
	if (level.kind === LevelKind.Tabs) {
		const pages = level.pages as ChildPages<Stop, Place>;
		const current = pages.pages();
		let at: int32 = -1;
		for (let i = 0; i < current.items.length; i += 1) {
			if (current.items[i].route === route) { at = i as int32; }
		}
		if (at < 0) { throw new Error("routing: a tab level has no page for a matched route"); }
		const page = current.items[at];
		if (page.path !== routePath) {
			const items = current.items.slice(0);
			items[at] = stopOf(routes, chain, depth, target.search, target.hash, seed, 0, target.intent);
			level.visit(at);
			pages.navigate((previous: Pages<Stop>): Pages<Stop> => ({ items, selectedIndex: at }));
			return Walked.Changed;
		}
		const switched = at !== current.selectedIndex;
		if (switched) {
			level.visit(at);
			pages.select(at);
		}
		if (leaf) {
			const left = walkLeaf(page, target, (next: Stop): void => {
				const items = current.items.slice(0);
				items[at] = next;
				pages.navigate((previous: Pages<Stop>): Pages<Stop> => ({ items, selectedIndex: at }));
			});
			return switched ? Walked.Changed : left;
		}
		const child = untrack((): NavigationChild<Stop, Place> => pages.items()[at]);
		const below = walk(routes, child.instance.level as Level, target, depth + 1);
		return switched ? Walked.Changed : below;
	}
	const stack = level.stack as ChildStack<Stop, Place>;
	const stops = stack.configurations();
	const top = stops[stops.length - 1];
	if (top.route === route && top.path === routePath) {
		if (leaf) {
			return walkLeaf(top, target, (next: Stop): void => stack.replaceCurrent(next));
		}
		const child = untrack((): NavigationChild<Stop, Place> => stack.active());
		return walk(routes, child.instance.level as Level, target, depth + 1);
	}
	const skip: int32 = target.replace ? (stops.length - 1) as int32 : -1;
	const next = stopOf(
		routes,
		chain,
		depth,
		target.search,
		target.hash,
		seed,
		freeVisit(stops, route, routePath, skip),
		target.intent,
	);
	if (target.replace) { stack.replaceCurrent(next); } else { stack.push(next); }
	return Walked.Changed;
}

function targetOf(resolved: Resolved, replace: boolean, intent: PreloadIntent): Target {
	const match = resolved.match;
	return {
		chain: match.chain,
		search: match.search,
		hash: match.hash,
		seed: pathnameOf(resolved.address),
		replace,
		intent,
	};
}

function leafStop(root: Level): Stop {
	let level = root;
	while (true) {
		const child = activeChild(level);
		const nested = child.instance.level;
		if (nested === null) { return child.configuration(); }
		level = nested as Level;
	}
	throw new Error("routing: unreachable");
}

function matchOf(routes: Routes, root: Level): RouteMatch {
	const chain: MatchedRoute[] = [];
	let level = root;
	while (true) {
		const child = activeChild(level);
		const stop = child.configuration();
		chain.push({ node: routes.views[stop.route].node, path: stop.path, params: stop.params });
		const nested = child.instance.level;
		if (nested === null) { return { chain, search: stop.search, hash: stop.hash }; }
		level = nested as Level;
	}
	throw new Error("routing: unreachable");
}

struct RouterEntry {
	web: string;
	address: string;
	document: string;
}

export class Router {
	routes: Routes;
	match: Accessor<RouteMatch>;
	location: Accessor<RouterLocation>;
	private root: Level;
	private current: Signal<Resolved>;
	private history: RoutingHistory;
	private session: RoutingSession | null = null;
	private stop: Dispose | null = null;
	private group: (change: () => void, visit: boolean) => void = (change: () => void, visit: boolean): void => { flush(change); };

	constructor(routes: Routes, root: Level, current: Signal<Resolved>, history: RoutingHistory) {
		this.routes = routes;
		this.root = root;
		this.current = current;
		this.history = history;
		this.match = accessor((): RouteMatch => matchOf(routes, root));
		this.location = accessor((): RouterLocation => {
			const stop = leafStop(root);
			return { pathname: stop.path, search: stop.search, hash: stop.hash };
		});
	}

	view(): NeonNode {
		const steer: Steer = {
			navigate: (href: string): boolean => this.navigate(href),
			popToRoot: (stack: ChildStack<Stop, Place>): void => {
				this.group((): void => { stack.popTo(0); }, false);
				const settled = follow(this.routes.tree, addressOf(untrack((): Stop => leafStop(this.root))));
				if (settled.ok) { this.current.set(settled.value); }
			},
		};
		return levelView(this.routes, this.root, steer, null);
	}

	connect(session: RoutingSession, stop: Dispose | null, group: (change: () => void, visit: boolean) => void): void {
		this.session = session;
		this.stop = stop;
		this.group = group;
	}

	apply(resolved: Resolved, replace: boolean, visit: boolean = false, intent: PreloadIntent = "native"): Walked {
		let walked = Walked.Unchanged;
		this.group((): void => {
			walked = walk(this.routes, this.root, targetOf(resolved, replace, intent), 0);
			this.current.set(resolved);
		}, visit);
		return walked;
	}

	settle(resolved: Resolved, stored: string): void {
		if (resolved.redirect === 0 && resolved.address === stored) {
			const leaf = untrack((): Stop => leafStop(this.root));
			if (leaf.path === pathnameOf(resolved.address)) {
				this.apply(resolved, false);
			} else {
				this.current.set(resolved);
			}
			return;
		}
		this.apply(resolved, true);
	}

	navigate<P>(options: ToOptions<P>): boolean {
		const built = hrefOf<P>(this.routes.tree, options.to, options.params, options.search ?? new Map<string, string>());
		if (!built.ok) { throw new Error("routing: navigate({ to }) cannot build an address for " + (options.to.node.pattern ?? "a pathless route") + ": " + built.error.toString()); }
		return this.navigate(built.value, { replace: options.replace ?? false });
	}

	navigate(href: string, options: NavigateOptions | null = null): boolean {
		if (!this.history.writable) { throw new Error("routing: request history is read-only"); }
		const replace = options === null ? false : (options as NavigateOptions).replace ?? false;
		const resolved = follow(this.routes.tree, href);
		if (!resolved.ok) { return false; }
		const walked = this.apply(resolved.value, replace, !replace, "navigate");
		const session = this.session;
		if (walked === Walked.HashOnly && session !== null) {
			return (session as RoutingSession).sync(replace).ok;
		}
		return true;
	}

	preload(href: string): void {
		const found = this.routes.tree.match(href);
		if (!found.ok) { return; }
		const match = found.value;
		const location: RouterLocation = { pathname: pathnameOf(href), search: match.search, hash: match.hash };
		for (const level of match.chain) {
			const preload = level.node.preload;
			if (preload !== null) {
				untrack((): number => {
					(preload as (args: PreloadArgs<Map<string, string>>) => void)({ params: level.params, location, intent: "preload" });
					return 0;
				});
			}
		}
	}

	go(delta: int32): boolean {
		if (!this.history.writable) { throw new Error("routing: request history is read-only"); }
		return this.history.go(delta);
	}

	canGoBack(): boolean {
		const session = this.session;
		return session !== null && (session as RoutingSession).canGoBack();
	}

	response(): RouterResponse {
		const resolved = untrack((): Resolved => this.current.get());
		if (resolved.redirect !== 0) { return { status: resolved.redirect, location: resolved.address }; }
		return { status: resolved.status, location: null };
	}

	dispose(): void {
		const stop = this.stop;
		if (stop !== null) { (stop as Dispose)(); }
		const session = this.session;
		if (session !== null) { (session as RoutingSession).dispose(); }
	}
}

function resolvesOnReload(routes: Routes, resolved: Resolved): boolean {
	const chain = resolved.match.chain;
	return routes.views[idOf(routes, chain[chain.length - 1].node)].resolveOnReload;
}

function participantOf(router: Router, web: WebHistory, tree: RouteTree, root: Level): RoutingParticipant {
	const document = Math.round(Math.random() * 10000000).toString();
	const withHash = (base: string): string => {
		const leaf = untrack((): Stop => leafStop(root));
		if (leaf.hash === "" || pathnameOf(base) !== leaf.path) { return base; }
		return base + "#" + leaf.hash;
	};
	return {
		scope: "main",
		prepare: web.participant.prepare,
		address: (): Result<string | null, RoutingError> => {
			const base = try web.participant.address();
			if (base === null) { return Result.ok(null); }
			const address: string | null = withHash(base as string);
			return Result.ok(address);
		},
		capture: (): string => {
			const base = web.participant.address();
			let address = "";
			if (base.ok) {
				const value = base.value;
				if (value !== null) { address = withHash(value as string); }
			}
			const entry: RouterEntry = { web: web.participant.capture(), address, document };
			return JSON.stringify(entry);
		},
		restore: (state: string, address: string | null): Result<RoutePlan, RoutingError> => {
			const parsed = JSON.parse<RouterEntry>(state);
			if (!parsed.ok && address === null) { return Result.err(RoutingError.IncompleteSnapshot); }
			const entry: RouterEntry = parsed.ok ? parsed.value : { web: "", address: address as string, document: "" };
			const resolved = try follow(tree, entry.address);
			const reloaded = entry.document !== document && resolvesOnReload(router.routes, resolved);
			const plan = try web.participant.restore(reloaded ? "" : entry.web, address);
			return Result.ok(web.suppressed((): void => {
				plan.commit();
				router.settle(resolved, entry.address);
			}));
		},
	};
}

export function createRouter(routes: Routes, history: RoutingHistory): Result<Router, RoutingError> {
	const first = try follow(routes.tree, history.read().url);
	const none = new Map<string, string>();
	const from: Stop = {
		route: -1,
		visit: 0,
		seed: pathnameOf(first.address),
		path: "",
		part: "",
		params: none,
		search: first.match.search,
		hash: first.match.hash,
		intent: "initial",
	};
	const seeding: Seeding = { cold: true };
	const root = createLevel(routes, -1, "", first.match.chain, 0, from, seeding);
	const current = new Signal<Resolved>(first);
	const router = new Router(routes, root, current, history);
	const web = createWebHistory(
		"main",
		root.owner.webNavigation,
		(address: string | null): Result<RoutePlan, RoutingError> => {
			if (address === null) { return Result.err(RoutingError.NoMatch); }
			const resolved = try follow(routes.tree, address as string);
			return Result.ok({ commit: (): void => { router.apply(resolved, false); } });
		},
	);
	const registry = new RoutingRegistry("main");
	registry.register(participantOf(router, web, routes.tree, root));
	const opened = createRoutingSession(registry, history, (failure: RoutingError): void => {});
	if (!opened.ok) {
		root.dispose();
		return Result.err(opened.error);
	}
	const session = opened.value;
	router.connect(session, history.writable ? web.enable(session) : null, web.grouped);
	seeding.cold = false;
	return Result.ok(router);
}

interface RouteScope {
	params: Map<string, string>;
	node: RouteNode;
	parent: RouteScope | null;
}

const RouterContext = createContext<Router | null>(null);
const RouteContext = createContext<RouteScope | null>(null);

function mountLater(make: () => NeonNode): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		untrack((): number => { make()(host, parent, before); return 0; });
	};
}

interface Steer {
	navigate: (href: string) => boolean;
	popToRoot: (stack: ChildStack<Stop, Place>) => void;
}

function addressOf(stop: Stop): string {
	let address = stop.path;
	let first = true;
	for (const name of stop.search) {
		address += (first ? "?" : "&") + encodeRouteComponent(name) + "=" + encodeRouteComponent(stop.search.get(name) ?? "");
		first = false;
	}
	return stop.hash === "" ? address : address + "#" + stop.hash;
}

function leafOf(child: NavigationChild<Stop, Place>): Stop {
	const level = child.instance.level;
	return level === null ? child.configuration() : leafStop(level as Level);
}

function tabTrigger(
	routes: Routes,
	pages: ChildPages<Stop, Place>,
	child: NavigationChild<Stop, Place>,
	at: Accessor<number>,
	steer: Steer,
): TabTrigger {
	const view = routes.views[untrack((): Stop => child.configuration()).route];
	const options = accessor((): ScreenOptions => readOptions(view.options));
	const focused = accessor((): boolean => pages.selectedIndex() === at());
	const href = accessor((): string | null => addressOf(leafOf(child)));
	return {
		key: child.key,
		label: accessor((): string => {
			const part = child.configuration().part;
			return options().tabBarLabel ?? options().title ?? (part === "" ? "index" : part);
		}),
		options,
		focused,
		href,
		press: (): void => {
			if (!untrack((): boolean => focused())) {
				const target = untrack((): string => addressOf(leafOf(child)));
				if (!steer.navigate(target)) {
					throw new Error("routing: the tab " + view.label + " opens " + target + ", which no route matches");
				}
				return;
			}
			const nested = child.instance.level;
			if (nested === null || (nested as Level).kind !== LevelKind.Stack) { return; }
			const stack = (nested as Level).stack as ChildStack<Stop, Place>;
			if (untrack((): Stop[] => stack.configurations()).length > 1) { steer.popToRoot(stack); }
		},
	};
}

function tabTriggers(routes: Routes, level: Level, steer: Steer): Accessor<TabTrigger[]> {
	const pages = level.pages as ChildPages<Stop, Place>;
	return mapArray<NavigationChild<Stop, Place>, TabTrigger>(
		(): NavigationChild<Stop, Place>[] => pages.items(),
		(child: NavigationChild<Stop, Place>, at: Accessor<number>): TabTrigger => tabTrigger(routes, pages, child, at, steer),
	);
}

function levelView(routes: Routes, level: Level, steer: Steer, parent: RouteScope | null): NeonNode {
	const render = (child: NavigationChild<Stop, Place>): NeonNode => placeView(routes, child, steer, parent);
	return match (level.kind) {
		LevelKind.Slot => renderStackTop<Stop, Place>(level.stack as ChildStack<Stop, Place>, render),
		LevelKind.Stack => renderStack<Stop, Place>(level.stack as ChildStack<Stop, Place>, render, (child: NavigationChild<Stop, Place>): boolean => {
			return routes.views[untrack((): Stop => child.configuration()).route].presentation === "transparentModal";
		}),
		LevelKind.Tabs => renderPages<Stop, Place>(level.pages as ChildPages<Stop, Place>, render),
	};
}

function tabsFrame(inner: NeonNode): NeonNode {
	return <View style={{ flex: 1, flexDirection: "column" }}>
		<View style={{ flex: 1, flexDirection: "column", position: "relative" }}>{inner}</View>
		<TabBar />
	</View>;
}

function placeView(routes: Routes, child: NavigationChild<Stop, Place>, steer: Steer, parent: RouteScope | null): NeonNode {
	const stop = untrack((): Stop => child.configuration());
	const found = routes.views[stop.route];
	const scope: RouteScope = { params: stop.params, node: found.node, parent };
	const preload = found.node.preload;
	if (preload !== null) {
		const leaf = leafOf(child);
		const location: RouterLocation = { pathname: leaf.path, search: leaf.search, hash: leaf.hash };
		untrack((): number => {
			(preload as (args: PreloadArgs<Map<string, string>>) => void)({ params: stop.params, location, intent: stop.intent });
			return 0;
		});
	}
	const component = found.component;
	const layout = found.layout;
	let body: NeonNode;
	if (component !== null) {
		body = mountLater(component as () => NeonNode);
	} else {
		const level = child.instance.level as Level;
		const inner = levelView(routes, level, steer, scope);
		if (layout !== null) {
			body = createComponent<LayoutProps>(layout as (props: LayoutProps) => NeonNode, { children: inner });
		} else if (level.kind === LevelKind.Tabs) {
			body = tabsFrame(inner);
		} else {
			body = inner;
		}
		if (level.kind === LevelKind.Tabs) {
			const list: TabList = { tabs: tabTriggers(routes, level, steer) };
			const framed = body;
			body = <TabsContext value={list}>{framed}</TabsContext>;
		}
	}
	return <RouteContext value={scope}>{body}</RouteContext>;
}

export function RouterProvider(props: { router: Router }): NeonNode {
	const router = props.router;
	return <RouterContext value={router}>{router.view()}</RouterContext>;
}

function useRouter(caller: string): Router {
	const router = useContext(RouterContext);
	if (router === null) { throw new Error("routing: " + caller + " is called outside a RouterProvider"); }
	return router as Router;
}

export function useParams(): Map<string, string> {
	const scope = useContext(RouteContext);
	if (scope === null) { throw new Error("routing: useParams is called outside a routed component"); }
	return (scope as RouteScope).params;
}

export function useParams<P>(options: { from: RouteDef<P> }): P {
	const from = options.from;
	let scope = useContext(RouteContext);
	if (scope === null) { throw new Error("routing: useParams is called outside a routed component"); }
	while (scope !== null) {
		const level = scope as RouteScope;
		if (level.node === from.node) {
			const parsed = from.params.parse(level.params);
			if (!parsed.ok) { throw new Error("routing: the params of " + (from.node.pattern ?? "a pathless route") + " do not parse: " + parsed.error.toString()); }
			return parsed.value;
		}
		scope = level.parent;
	}
	throw new Error("routing: useParams({ from }) names " + (from.node.pattern ?? "a pathless route") + ", which is not on this component's route");
}

export function useNavigate(): (to: string | int32, options?: NavigateOptions | null) => boolean {
	const router = useRouter("useNavigate");
	return (to: string | int32, options: NavigateOptions | null = null): boolean => {
		if (typeof to === "string") { return router.navigate(to, options); }
		return router.go(to as int32);
	};
}

export function useLocation(): Accessor<RouterLocation> {
	return useRouter("useLocation").location;
}

export function useMatch(pattern: string): Accessor<PathMatch | null> {
	const location = useRouter("useMatch").location;
	const matchers: ((location: string) => PathMatch | null)[] = [];
	for (const expanded of expandOptionals(normalizePath(pattern))) { matchers.push(createMatcher(expanded)); }
	return accessor((): PathMatch | null => {
		const pathname = location().pathname;
		for (const matcher of matchers) {
			const found = matcher(pathname);
			if (found !== null) { return found; }
		}
		return null;
	});
}

function comparable(address: string): string {
	const lower = normalizePath(pathnameOf(address)).toLowerCase();
	const trimmed = lower.endsWith("/") ? lower.substring(0, lower.length - 1) : lower;
	const decoded = decodeRouteComponent(trimmed);
	return decoded.ok ? decoded.value : trimmed;
}

export function A(props: { href: Accessor<string>; children: NeonNode }): NeonNode {
	const location = useRouter("A").location;
	const href = props.href;
	const current = accessor((): string | null => {
		return comparable(href()) === comparable(location().pathname) ? "page" : null;
	});
	return <a href={href()} aria-current={current()}>{props.children}</a>;
}
