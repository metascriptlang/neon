import { RoutingError, encodeRouteComponent, decodeRouteComponent } from "./routing";
import {
	PathMatch,
	joinPaths,
	normalizePath,
	createMatcher,
	scoreRoute,
	expandOptionals,
	encodePattern,
	routePatterns,
} from "./routeMatcher";

export interface ParamsCodec<P> {
	parse: (values: Map<string, string>) => Result<P, RoutingError>;
	stringify: (params: P) => Map<string, string>;
}

export enum GuardAction {
	Continue,
	Redirect,
	NotFound,
}

export struct GuardDecision {
	action: GuardAction;
	address: string;
	status: int32;
}

export function proceed(): GuardDecision {
	return { action: GuardAction.Continue, address: "", status: 0 };
}

export function redirect(address: string, status: int32 = 307): GuardDecision {
	return { action: GuardAction.Redirect, address, status };
}

export function notFound(): GuardDecision {
	return { action: GuardAction.NotFound, address: "", status: 404 };
}

export interface RouteNode {
	pattern: string | null;
	status: int32;
	acceptsAll: boolean;
	accepts: (values: Map<string, string>) => boolean;
	guard: ((values: Map<string, string>, found: RouteMatch) => GuardDecision) | null;
	paths: (() => Map<string, string>[]) | null;
}

export interface RouteDef<P> {
	node: RouteNode;
	params: ParamsCodec<P>;
}

export interface RouteOptions<P> {
	params: ParamsCodec<P>;
	guard?: ((params: P, found: RouteMatch) => GuardDecision) | null;
	status?: int32 | null;
	paths?: (() => P[]) | null;
}

export interface PathOptions {
	guard?: ((params: Map<string, string>, found: RouteMatch) => GuardDecision) | null;
	status?: int32 | null;
	paths?: (() => Map<string, string>[]) | null;
}

export interface RouteEntry {
	node: RouteNode;
	children?: RouteEntry[] | null;
}

export interface MatchedRoute {
	node: RouteNode;
	path: string;
	params: Map<string, string>;
}

export interface RouteMatch {
	chain: MatchedRoute[];
	search: Map<string, string>;
	hash: string;
}

export interface RouteResolution {
	match: RouteMatch;
	status: int32;
	redirect: string | null;
}

export interface RouteTree {
	match: (address: string, through?: RouteNode | null) => Result<RouteMatch, RoutingError>;
	resolve: (address: string) => Result<RouteResolution, RoutingError>;
	href: (
		node: RouteNode,
		values: Map<string, string>,
		search: Map<string, string>,
	) => Result<string, RoutingError>;
	staticPaths: () => Result<string[], RoutingError>;
}

function typedGuard<P>(
	codec: ParamsCodec<P>,
	guard: (params: P, found: RouteMatch) => GuardDecision,
): (values: Map<string, string>, found: RouteMatch) => GuardDecision {
	return (values: Map<string, string>, found: RouteMatch): GuardDecision => {
		const parsed = codec.parse(values);
		if (!parsed.ok) {
			throw new Error("routing: the params of a matched route no longer parse");
		}
		return guard(parsed.value, found);
	};
}

function typedPaths<P>(codec: ParamsCodec<P>, paths: () => P[]): () => Map<string, string>[] {
	return (): Map<string, string>[] => {
		const values: Map<string, string>[] = [];
		for (const params of paths()) { values.push(codec.stringify(params)); }
		return values;
	};
}

function routeDef<P>(
	pattern: string | null,
	options: RouteOptions<P>,
	acceptsAll: boolean,
): RouteDef<P> {
	const codec = options.params;
	const guard = options.guard;
	const paths = options.paths;
	const node: RouteNode = {
		pattern,
		status: options.status ?? 200,
		acceptsAll,
		accepts: (values: Map<string, string>): boolean => codec.parse(values).ok,
		guard: guard === null ? null : typedGuard<P>(codec, guard),
		paths: paths === null ? null : typedPaths<P>(codec, paths),
	};
	return { node, params: codec };
}

export function route<P>(pattern: string | null, options: RouteOptions<P>): RouteDef<P> {
	return routeDef<P>(pattern, options, false);
}

const identity: ParamsCodec<Map<string, string>> = {
	parse: (values: Map<string, string>): Result<Map<string, string>, RoutingError> => {
		return Result.ok(values);
	},
	stringify: (params: Map<string, string>): Map<string, string> => params,
};

export function path(
	pattern: string | null,
	options: PathOptions = {},
): RouteDef<Map<string, string>> {
	return routeDef<Map<string, string>>(pattern, {
		params: identity,
		guard: options.guard,
		status: options.status,
		paths: options.paths,
	}, true);
}

export function hrefOf<P>(
	tree: RouteTree,
	target: RouteDef<P>,
	params: P,
	search: Map<string, string>,
): Result<string, RoutingError> {
	return tree.href(target.node, target.params.stringify(params), search);
}

export function paramsOf<P>(target: RouteDef<P>, found: RouteMatch): Result<P, RoutingError> {
	for (const level of found.chain) {
		if (level.node === target.node) { return target.params.parse(level.params); }
	}
	return Result.err(RoutingError.NoMatch);
}

interface Placed {
	node: RouteNode;
	pattern: string;
	label: string;
	leaf: boolean;
}

interface Param {
	name: string;
	owner: string;
}

interface Level {
	node: RouteNode;
	pattern: string;
	leaf: boolean;
}

interface Branch {
	levels: Level[];
	matchers: ((location: string) => PathMatch | null)[];
	score: int32;
	kinds: int32[];
	shape: string;
	order: int32;
}

function childrenOf(entry: RouteEntry): RouteEntry[] {
	const children = entry.children;
	return children === null ? [] : children as RouteEntry[];
}

function wordsOf(name: string): string {
	let words = "";
	for (let i: int32 = 0; i < name.byteLength(); i += 1) {
		const byte = name.byteAt(i);
		if ((byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) ||
			(byte >= 48 && byte <= 57) || byte === 95 || byte >= 128) {
			words += String.fromCharCode(byte);
		}
	}
	return words;
}

function paramName(segment: string): string {
	if (segment.startsWith("*")) { return segment.substring(1, segment.length); }
	const optional = segment.endsWith("?");
	return segment.substring(1, optional ? segment.length - 1 : segment.length);
}

function labelOf(joined: string, pathless: boolean): string {
	const shown = joined === "" ? "/" : joined;
	return pathless ? shown + " (pathless)" : shown;
}

function declare(entries: RouteEntry[], base: string, params: Param[], places: Placed[]): void {
	for (const entry of entries) {
		const node = entry.node;
		const children = childrenOf(entry);
		const leaf = children.length === 0;
		const own = node.pattern === null ? "" : node.pattern as string;
		const joined = joinPaths(base, own);
		const label = labelOf(joined, node.pattern === null);
		for (const place of places) {
			if (place.node === node) {
				throw new Error(
					"routing: one route is declared at \"" + place.label + "\" and at \"" +
						label + "\"",
				);
			}
		}
		const segments: string[] = [];
		for (const segment of own.split("/")) {
			if (segment !== "") { segments.push(segment); }
		}
		const known = params.slice(0);
		for (let i: int32 = 0; i < segments.length; i += 1) {
			const segment = segments[i];
			if (segment.startsWith("*") && i < segments.length - 1) {
				throw new Error("routing: the splat of \"" + label + "\" is not its last segment");
			}
			if (segment.startsWith("*") && !leaf) {
				const child = children[0].node.pattern;
				const childLabel = labelOf(
					joined + normalizePath(child === null ? "" : child as string),
					child === null,
				);
				throw new Error(
					"routing: the splat of \"" + label + "\" is not the last segment of \"" +
						childLabel + "\"",
				);
			}
			if (!segment.startsWith(":") && !segment.startsWith("*")) { continue; }
			const name = paramName(segment);
			if (name === "") { continue; }
			for (const param of known) {
				if (param.name === name) {
					throw new Error(
						"routing: \"" + param.owner + "\" and \"" + label +
							"\" both name the param \"" + name + "\"",
					);
				}
				if (wordsOf(param.name) === wordsOf(name)) {
					throw new Error(
						"routing: the param names \"" + param.name + "\" of \"" + param.owner +
							"\" and \"" + name + "\" of \"" + label +
							"\" differ only by non-word symbols",
					);
				}
			}
			known.push({ name, owner: label });
		}
		places.push({ node, pattern: encodePattern(joined), label, leaf });
		if (!leaf) { declare(children, joined, known, places); }
	}
}

function kindOf(segment: string): int32 {
	if (segment.startsWith("*")) { return 2; }
	return segment.startsWith(":") ? 1 : 0;
}

function branchOf(levels: Level[], order: int32): Branch {
	const matchers: ((location: string) => PathMatch | null)[] = [];
	for (const level of levels) { matchers.push(createMatcher(level.pattern, !level.leaf)); }
	const pattern = levels[levels.length - 1].pattern;
	const kinds: int32[] = [];
	const shape: string[] = [];
	for (const segment of pattern.split("/")) {
		if (segment === "") { continue; }
		const kind = kindOf(segment);
		kinds.push(kind);
		shape.push(kind === 2 ? "*" : kind === 1 ? ":" : segment.toLowerCase());
	}
	return {
		levels,
		matchers,
		score: scoreRoute(pattern),
		kinds,
		shape: "/" + shape.join("/"),
		order,
	};
}

function collect(entries: RouteEntry[], base: string, stack: Level[], branches: Branch[]): void {
	for (const entry of entries) {
		const node = entry.node;
		const children = childrenOf(entry);
		const leaf = children.length === 0;
		const own = node.pattern === null ? "" : node.pattern as string;
		for (const pattern of routePatterns(own, base, leaf)) {
			const levels = stack.slice(0);
			levels.push({ node, pattern, leaf });
			if (leaf) {
				branches.push(branchOf(levels, branches.length as int32));
			} else {
				collect(children, pattern, levels, branches);
			}
		}
	}
}

function labelFor(places: Placed[], node: RouteNode): string {
	for (const place of places) {
		if (place.node === node) { return place.label; }
	}
	return "";
}

function leafOf(branch: Branch): RouteNode {
	return branch.levels[branch.levels.length - 1].node;
}

function acceptsAll(branch: Branch): boolean {
	for (const level of branch.levels) {
		if (!level.node.acceptsAll) { return false; }
	}
	return true;
}

function checkShapes(branches: Branch[], places: Placed[]): void {
	for (let i: int32 = 0; i < branches.length; i += 1) {
		for (let j: int32 = 0; j < i; j += 1) {
			const earlier = leafOf(branches[j]);
			const later = leafOf(branches[i]);
			const same = branches[j].shape === branches[i].shape;
			if (same && earlier !== later && acceptsAll(branches[j])) {
				throw new Error(
					"routing: \"" + labelFor(places, earlier) + "\" and \"" +
						labelFor(places, later) + "\" match the same addresses",
				);
			}
		}
	}
}

function ranksBefore(a: Branch, b: Branch): boolean {
	if (a.score !== b.score) { return a.score > b.score; }
	for (let i: int32 = 0; i < a.kinds.length && i < b.kinds.length; i += 1) {
		if (a.kinds[i] !== b.kinds[i]) { return a.kinds[i] < b.kinds[i]; }
	}
	if (a.kinds.length !== b.kinds.length) { return a.kinds.length < b.kinds.length; }
	return a.order < b.order;
}

function rank(branches: Branch[]): Branch[] {
	let ranked: Branch[] = [];
	for (const branch of branches) {
		const next: Branch[] = [];
		let placed = false;
		for (const other of ranked) {
			if (!placed && ranksBefore(branch, other)) {
				next.push(branch);
				placed = true;
			}
			next.push(other);
		}
		if (!placed) { next.push(branch); }
		ranked = next;
	}
	return ranked;
}

function matchBranch(branch: Branch, pathname: string): MatchedRoute[] | null {
	const last = branch.levels.length - 1;
	const leafMatch = branch.matchers[last](pathname);
	if (leafMatch === null) { return null; }
	const chain: MatchedRoute[] = [];
	for (let i: int32 = 0; i <= last; i += 1) {
		const level = i === last ? leafMatch : branch.matchers[i](pathname);
		if (level === null) { return null; }
		const node = branch.levels[i].node;
		const found = level as PathMatch;
		if (!node.accepts(found.params)) { return null; }
		chain.push({ node, path: found.path, params: found.params });
	}
	return chain;
}

function decodeSearch(text: string): Result<string, RoutingError> {
	return decodeRouteComponent(text.replaceAll("+", " "));
}

function parseSearch(query: string): Result<Map<string, string>, RoutingError> {
	const search = new Map<string, string>();
	for (const pair of query.split("&")) {
		if (pair === "") { continue; }
		const equalAt = pair.indexOf("=");
		const name = try decodeSearch(equalAt < 0 ? pair : pair.substring(0, equalAt));
		const value = try decodeSearch(equalAt < 0 ? "" : pair.substring(equalAt + 1, pair.length));
		if (!search.has(name)) { search.set(name, value); }
	}
	return Result.ok(search);
}

interface Address {
	pathname: string;
	search: Map<string, string>;
	hash: string;
}

function splitAddress(address: string): Result<Address, RoutingError> {
	const hashAt = address.indexOf("#");
	const hash = hashAt < 0 ? "" : address.substring(hashAt + 1, address.length);
	const rest = hashAt < 0 ? address : address.substring(0, hashAt);
	const queryAt = rest.indexOf("?");
	const pathname = queryAt < 0 ? rest : rest.substring(0, queryAt);
	const _decoded = try decodeRouteComponent(pathname);
	const search = try parseSearch(queryAt < 0 ? "" : rest.substring(queryAt + 1, rest.length));
	return Result.ok({ pathname, search, hash });
}

function passes(chain: MatchedRoute[], node: RouteNode): boolean {
	for (const level of chain) {
		if (level.node === node) { return true; }
	}
	return false;
}

function matchAddress(
	ranked: Branch[],
	address: string,
	through: RouteNode | null,
): Result<RouteMatch, RoutingError> {
	const parts = try splitAddress(address);
	for (const branch of ranked) {
		const chain = matchBranch(branch, parts.pathname);
		if (chain !== null && (through === null || passes(chain as MatchedRoute[], through as RouteNode))) {
			return Result.ok({ chain: chain as MatchedRoute[], search: parts.search, hash: parts.hash });
		}
	}
	return Result.err(RoutingError.NoMatch);
}

function decide(found: RouteMatch): GuardDecision {
	for (const level of found.chain) {
		const guard = level.node.guard;
		if (guard === null) { continue; }
		const decision = guard(level.params, found);
		if (decision.action !== GuardAction.Continue) { return decision; }
	}
	return proceed();
}

function resolveAddress(ranked: Branch[], address: string): Result<RouteResolution, RoutingError> {
	const parts = try splitAddress(address);
	for (const branch of ranked) {
		const chain = matchBranch(branch, parts.pathname);
		if (chain === null) { continue; }
		const found: RouteMatch = { chain: chain as MatchedRoute[], search: parts.search, hash: parts.hash };
		const decision = decide(found);
		if (decision.action === GuardAction.NotFound) { continue; }
		if (decision.action === GuardAction.Redirect) {
			return Result.ok({ match: found, status: decision.status, redirect: decision.address });
		}
		const leaf = found.chain[found.chain.length - 1].node;
		return Result.ok({ match: found, status: leaf.status, redirect: null });
	}
	return Result.err(RoutingError.NoMatch);
}

function buildPath(pattern: string, values: Map<string, string>): Result<string, RoutingError> {
	let built = "";
	for (const segment of pattern.split("/")) {
		if (segment === "") { continue; }
		const kind = kindOf(segment);
		if (kind === 0) {
			built += "/" + segment;
			continue;
		}
		const value = values.get(paramName(segment));
		const absent = value === null || value === "";
		if (kind === 1 && absent && !segment.endsWith("?")) {
			return Result.err(RoutingError.InvalidParams);
		}
		if (absent) { continue; }
		const pieces = kind === 2 ? (value as string).split("/") : [value as string];
		for (const piece of pieces) {
			if (piece === "") { return Result.err(RoutingError.InvalidParams); }
			built += "/" + encodeRouteComponent(piece);
		}
	}
	return Result.ok(built === "" ? "/" : built);
}

function searchText(search: Map<string, string>): string {
	const pairs: string[] = [];
	for (const [name, value] of search) {
		pairs.push(encodeRouteComponent(name) + "=" + encodeRouteComponent(value));
	}
	return pairs.length === 0 ? "" : "?" + pairs.join("&");
}

function hasParams(pattern: string): boolean {
	for (const segment of pattern.split("/")) {
		if (segment !== "" && kindOf(segment) !== 0) { return true; }
	}
	return false;
}

function staticPathsOf(places: Placed[]): Result<string[], RoutingError> {
	const paths: string[] = [];
	const none = new Map<string, string>();
	for (const place of places) {
		if (!place.leaf) { continue; }
		const enumerate = place.node.paths;
		if (enumerate !== null) {
			for (const values of enumerate()) { paths.push(try buildPath(place.pattern, values)); }
			continue;
		}
		for (const expanded of expandOptionals(place.pattern)) {
			if (!hasParams(expanded)) { paths.push(try buildPath(expanded, none)); }
		}
	}
	return Result.ok(paths);
}

export function createRouteTree(entries: RouteEntry[]): RouteTree {
	const places: Placed[] = [];
	declare(entries, "", [], places);
	const branches: Branch[] = [];
	collect(entries, "", [], branches);
	checkShapes(branches, places);
	const ranked = rank(branches);
	return {
		match: (address: string, through: RouteNode | null = null): Result<RouteMatch, RoutingError> => {
			return matchAddress(ranked, address, through);
		},
		resolve: (address: string): Result<RouteResolution, RoutingError> => {
			return resolveAddress(ranked, address);
		},
		href: (
			node: RouteNode,
			values: Map<string, string>,
			search: Map<string, string>,
		): Result<string, RoutingError> => {
			for (const place of places) {
				if (place.node === node) {
					const built = try buildPath(place.pattern, values);
					return Result.ok(built + searchText(search));
				}
			}
			return Result.err(RoutingError.NoMatch);
		},
		staticPaths: (): Result<string[], RoutingError> => staticPathsOf(places),
	};
}
