import { Accessor, Signal, accessor, untrack } from "../core/signal";
import { createMemo } from "../core/memo";
import { Host, HostNode, NeonNode } from "../render/hostTypes";
import { createComponent } from "../render/component";
import { createContext, useContext } from "../render/context";
import { For } from "../macros/ui/flow";
import {
	RoutePlan,
	RoutingError,
	RoutingParticipant,
	RoutingRegistry,
	decodeRouteComponent,
} from "./routing";
import { RoutingHistory, RoutingSession, createRoutingSession } from "./routingHistory";
import { GuardDecision, RouteEntry, RouteMatch, RouteNode, RouteTree, createRouteTree, path } from "./route";
import { PathMatch, createMatcher, expandOptionals, normalizePath } from "./routeMatcher";

const MAX_REDIRECTS: int32 = 20;
const PERMANENT_REDIRECT: int32 = 308;

export interface LayoutProps {
	children: NeonNode;
}

export interface RouteConfig {
	path?: string | null;
	component?: (() => NeonNode) | null;
	layout?: ((props: LayoutProps) => NeonNode) | null;
	status?: int32 | null;
	guard?: ((params: Map<string, string>, found: RouteMatch) => GuardDecision) | null;
	paths?: (() => Map<string, string>[]) | null;
	children?: RouteConfig[] | null;
}

export interface RouteView {
	node: RouteNode;
	component: (() => NeonNode) | null;
	layout: ((props: LayoutProps) => NeonNode) | null;
}

export interface Routes {
	tree: RouteTree;
	views: RouteView[];
}

function labelOf(config: RouteConfig): string {
	const pattern = config.path;
	return pattern === null ? "a route without a path" : "\"" + (pattern as string) + "\"";
}

function compile(configs: RouteConfig[], views: RouteView[]): RouteEntry[] {
	const entries: RouteEntry[] = [];
	for (const config of configs) {
		const children = config.children ?? [];
		const leaf = children.length === 0;
		if (leaf && config.layout !== null) {
			throw new Error("routing: " + labelOf(config) + " has a layout but no children to lay out");
		}
		if (leaf && config.component === null) {
			throw new Error("routing: " + labelOf(config) + " has neither children nor a component");
		}
		if (!leaf && config.component !== null) {
			throw new Error("routing: " + labelOf(config) + " has children, so it takes a layout, not a component");
		}
		const node = path(config.path, { status: config.status, guard: config.guard, paths: config.paths }).node;
		views.push({ node, component: config.component, layout: config.layout });
		entries.push({ node, children: leaf ? null : compile(children, views) });
	}
	return entries;
}

export function createRoutes(configs: RouteConfig[]): Routes {
	const views: RouteView[] = [];
	const entries = compile(configs, views);
	return { tree: createRouteTree(entries), views };
}

export interface RouterLocation {
	pathname: string;
	search: Map<string, string>;
	hash: string;
}

export interface RouterResponse {
	status: int32;
	location: string | null;
}

export interface NavigateOptions {
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

export class Router {
	routes: Routes;
	match: Accessor<RouteMatch>;
	location: Accessor<RouterLocation>;
	private current: Signal<Resolved | null>;
	private session: RoutingSession;

	constructor(routes: Routes, current: Signal<Resolved | null>, session: RoutingSession) {
		this.routes = routes;
		this.current = current;
		this.session = session;
		const resolved = (): Resolved => {
			const now = current.get();
			if (now === null) { throw new Error("routing: the router has no resolved address"); }
			return now as Resolved;
		};
		this.match = accessor((): RouteMatch => resolved().match);
		this.location = accessor((): RouterLocation => {
			const now = resolved();
			return { pathname: pathnameOf(now.address), search: now.match.search, hash: now.match.hash };
		});
	}

	navigate(href: string, options: NavigateOptions | null = null): boolean {
		const replace = options === null ? false : (options as NavigateOptions).replace ?? false;
		return this.session.navigate(href, replace).ok;
	}

	response(): RouterResponse {
		const now = untrack((): Resolved | null => this.current.get());
		if (now === null) { throw new Error("routing: the router has no resolved address"); }
		const resolved = now as Resolved;
		if (resolved.redirect !== 0) { return { status: resolved.redirect, location: resolved.address }; }
		return { status: resolved.status, location: null };
	}

	dispose(): void {
		this.session.dispose();
	}
}

function participantOf(tree: RouteTree, current: Signal<Resolved | null>): RoutingParticipant {
	const plan = (address: string): Result<RoutePlan, RoutingError> => {
		const next = try follow(tree, address);
		return Result.ok({ commit: (): void => current.set(next) });
	};
	const held = (): Resolved | null => untrack((): Resolved | null => current.get());
	return {
		scope: "main",
		prepare: (address: string | null): Result<RoutePlan, RoutingError> => {
			if (address === null) { return Result.err(RoutingError.NoMatch); }
			return plan(address as string);
		},
		address: (): Result<string | null, RoutingError> => {
			const now = held();
			return Result.ok(now === null ? null : (now as Resolved).address);
		},
		capture: (): string => {
			const now = held();
			return now === null ? "" : (now as Resolved).address;
		},
		restore: (state: string): Result<RoutePlan, RoutingError> => plan(state),
	};
}

export function createRouter(routes: Routes, history: RoutingHistory): Result<Router, RoutingError> {
	const current = new Signal<Resolved | null>(null);
	const registry = new RoutingRegistry("main");
	registry.register(participantOf(routes.tree, current));
	const session = try createRoutingSession(registry, history, (failure: RoutingError): void => {});
	return Result.ok(new Router(routes, current, session));
}

interface RouteScope {
	params: Map<string, string>;
}

const RouterContext = createContext<Router | null>(null);
const RouteContext = createContext<RouteScope | null>(null);

interface Level {
	node: RouteNode;
	path: string;
	params: Map<string, string>;
}

function viewOf(routes: Routes, node: RouteNode): RouteView {
	for (const view of routes.views) {
		if (view.node === node) { return view; }
	}
	throw new Error("routing: a matched route has no view in its route tree");
}

function mountLater(make: () => NeonNode): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		untrack((): number => { make()(host, parent, before); return 0; });
	};
}

function view(router: Router, level: Level, depth: int32): NeonNode {
	const found = viewOf(router.routes, level.node);
	const scope: RouteScope = { params: level.params };
	const component = found.component;
	const layout = found.layout;
	let body: NeonNode;
	if (component !== null) {
		body = mountLater(component as () => NeonNode);
	} else if (layout !== null) {
		body = createComponent<LayoutProps>(
			layout as (props: LayoutProps) => NeonNode,
			{ children: outlet(router, depth + 1) },
		);
	} else {
		body = outlet(router, depth + 1);
	}
	return <RouteContext.Provider value={scope}>{body}</RouteContext.Provider>;
}

function outlet(router: Router, depth: int32): NeonNode {
	let held: Level | null = null;
	const shown = createMemo<Level[]>((): Level[] => {
		const chain = router.match().chain;
		if (depth >= chain.length) {
			held = null;
			return [];
		}
		const level = chain[depth];
		const kept = held;
		if (kept !== null && (kept as Level).node === level.node && (kept as Level).path === level.path) {
			return [kept as Level];
		}
		const next: Level = { node: level.node, path: level.path, params: level.params };
		held = next;
		return [next];
	});
	return <For each={shown}>{(level: Level): NeonNode => view(router, level, depth)}</For>;
}

export function RouterProvider(props: { router: Router }): NeonNode {
	const router = props.router;
	return <RouterContext.Provider value={router}>{outlet(router, 0)}</RouterContext.Provider>;
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

export function useNavigate(): (href: string, options?: NavigateOptions | null) => boolean {
	const router = useRouter("useNavigate");
	return (href: string, options: NavigateOptions | null = null): boolean => router.navigate(href, options);
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
