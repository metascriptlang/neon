import { NavTarget, NavigationState } from "./core";
import { QueryParams, encodeRouteComponent } from "./routing";

export interface LinkingScreen {
	name: string;
	path?: string | null;
	exact?: boolean | null;
	screens?: LinkingScreen[] | null;
}

export interface LinkingConfig {
	screens: LinkingScreen[];
}

export interface LinkingOptions {
	prefixes: string[];
	config: LinkingConfig;
	enabled?: boolean | null;
}

interface Segment {
	text: string;
	param: boolean;
	optional: boolean;
	wildcard: boolean;
	owner: int32;
}

interface Candidate {
	chain: string[];
	segments: Segment[];
	score: int32;
	order: int32;
}

function splitPath(path: string): string[] {
	const parts: string[] = [];
	for (const part of path.split("/")) {
		if (part !== "") { parts.push(part); }
	}
	return parts;
}

function patternSegments(path: string, owner: int32): Segment[] {
	const segments: Segment[] = [];
	for (const part of splitPath(path)) {
		if (part === "*") {
			segments.push({ text: "*", param: false, optional: false, wildcard: true, owner });
		} else if (part.startsWith(":")) {
			const optional = part.endsWith("?");
			const name = part.substring(1, optional ? part.length - 1 : part.length);
			segments.push({ text: name, param: true, optional, wildcard: false, owner });
		} else {
			segments.push({ text: part, param: false, optional: false, wildcard: false, owner });
		}
	}
	return segments;
}

function screenSegments(screen: LinkingScreen, prefix: Segment[], depth: int32): Segment[] {
	const exact = screen.exact;
	const fromRoot = exact !== null && (exact as boolean);
	const segments: Segment[] = fromRoot ? [] : prefix.slice(0, prefix.length);
	const own = screen.path;
	if (own !== null) {
		for (const segment of patternSegments(own as string, depth)) { segments.push(segment); }
	}
	return segments;
}

function collect(
	screens: LinkingScreen[],
	chain: string[],
	prefix: Segment[],
	out: Candidate[],
): void {
	for (const screen of screens) {
		const depth = chain.length as int32;
		const nextChain = chain.slice(0, chain.length);
		nextChain.push(screen.name);
		const own = screen.path;
		const segments = screenSegments(screen, prefix, depth);
		const nested = screen.screens;
		if (nested !== null) { collect(nested as LinkingScreen[], nextChain, segments, out); }
		if (own !== null) {
			let score: int32 = 0;
			for (const segment of segments) {
				if (segment.wildcard) {
					score -= 100;
				} else if (!segment.param) {
					score += 10;
				} else {
					score += 1;
				}
			}
			out.push({ chain: nextChain, segments, score, order: out.length as int32 });
		}
	}
}

function hexValue(byte: int32): int32 {
	if (byte >= 48 && byte <= 57) { return byte - 48; }
	if (byte >= 97 && byte <= 102) { return byte - 87; }
	if (byte >= 65 && byte <= 70) { return byte - 55; }
	return -1;
}

function percentByte(text: string, at: int32): int32 {
	if (at + 2 >= text.byteLength() || text.byteAt(at) !== 37) { return -1; }
	const high = hexValue(text.byteAt(at + 1));
	const low = hexValue(text.byteAt(at + 2));
	return high < 0 || low < 0 ? -1 : high * 16 + low;
}

function utf8Length(text: string, at: int32): int32 {
	const lead = percentByte(text, at);
	if (lead < 0) { return 0; }
	if (lead < 128) { return 1; }
	let length: int32 = 0;
	if (lead >= 194 && lead <= 223) { length = 2; }
	if (lead >= 224 && lead <= 239) { length = 3; }
	if (lead >= 240 && lead <= 244) { length = 4; }
	if (length === 0) { return 0; }
	let low: int32 = 128;
	let high: int32 = 191;
	if (lead === 224) { low = 160; }
	if (lead === 237) { high = 159; }
	if (lead === 240) { low = 144; }
	if (lead === 244) { high = 143; }
	for (let i: int32 = 1; i < length; i += 1) {
		const next = percentByte(text, at + 3 * i);
		if (next < low || next > high) { return 0; }
		low = 128;
		high = 191;
	}
	return length;
}

export function decodeComponent(text: string): string {
	if (text.indexOf("%") < 0) { return text; }
	const bytes: uint8[] = [];
	const length = text.byteLength();
	let i: int32 = 0;
	while (i < length) {
		const sequence = text.byteAt(i) === 37 ? utf8Length(text, i) : 0;
		if (sequence === 0) {
			bytes.push(text.byteAt(i) as uint8);
			i += 1;
		} else {
			for (let k: int32 = 0; k < sequence; k += 1) {
				bytes.push(percentByte(text, i + 3 * k) as uint8);
			}
			i += 3 * sequence;
		}
	}
	return bytes.asString();
}

function decodeParam(text: string): string | null {
	if (text.indexOf("%") < 0) { return text; }
	const length = text.byteLength();
	let i: int32 = 0;
	while (i < length) {
		if (text.byteAt(i) !== 37) {
			i += 1;
			continue;
		}
		const sequence = utf8Length(text, i);
		if (sequence === 0) { return null; }
		i += 3 * sequence;
	}
	return decodeComponent(text);
}

function parseQuery(query: string, into: QueryParams): void {
	let rest = query.trim();
	if (rest.startsWith("?") || rest.startsWith("#") || rest.startsWith("&")) {
		rest = rest.substring(1, rest.length);
	}
	const seen: string[] = [];
	for (const pair of rest.split("&")) {
		if (pair === "") { continue; }
		const spaced = pair.split("+").join(" ");
		const eq = spaced.indexOf("=");
		const name = decodeComponent(eq < 0 ? spaced : spaced.substring(0, eq));
		const value = eq < 0 ? "" : decodeComponent(spaced.substring(eq + 1, spaced.length));
		if (seen.indexOf(name) < 0) {
			seen.push(name);
			into.set(name, value);
		} else {
			into.append(name, value);
		}
	}
}

function matchFrom(
	segments: Segment[],
	from: int32,
	parts: string[],
	at: int32,
	values: QueryParams[],
): boolean {
	if (from >= segments.length) { return at >= parts.length; }
	const segment = segments[from];
	if (segment.wildcard) { return true; }
	if (segment.param) {
		if (at < parts.length) {
			const decoded = decodeParam(parts[at]);
			if (decoded === null) { return false; }
			values[segment.owner].set(segment.text, decoded as string);
			if (matchFrom(segments, from + 1, parts, at + 1, values)) { return true; }
			values[segment.owner].delete(segment.text);
		}
		return segment.optional && matchFrom(segments, from + 1, parts, at, values);
	}
	if (at >= parts.length || parts[at] !== segment.text) { return false; }
	return matchFrom(segments, from + 1, parts, at + 1, values);
}

function collapseSlashes(text: string): string {
	let out = "";
	let previousSlash = false;
	for (let i = 0; i < text.length; i += 1) {
		const char = text.charAt(i);
		const slash = char === "/";
		if (!(slash && previousSlash)) { out += char; }
		previousSlash = slash;
	}
	return out;
}

function isDelimiter(char: string): boolean {
	return char === "/" || char === "?" || char === "#";
}

function matchHost(labels: string[], label: int32, url: string, at: int32, closed: boolean): int32 {
	if (label >= labels.length) {
		if (closed || at >= url.length || isDelimiter(url.charAt(at))) { return at; }
		return -1;
	}
	let from = at;
	if (label > 0) {
		if (at >= url.length || url.charAt(at) !== ".") { return -1; }
		from = at + 1;
	}
	if (labels[label] !== "*") {
		const text = labels[label];
		if (url.substring(from, from + text.length) !== text) { return -1; }
		return matchHost(labels, label + 1, url, from + text.length, closed);
	}
	let end = from;
	while (end < url.length && !isDelimiter(url.charAt(end))) { end += 1; }
	for (let stop = end; stop > from; stop -= 1) {
		const matched = matchHost(labels, label + 1, url, stop, closed);
		if (matched >= 0) { return matched; }
	}
	return -1;
}

function pathAfterPrefix(url: string, prefix: string): string | null {
	const colon = prefix.indexOf(":");
	const protocol = colon > 0 ? prefix.substring(0, colon + 1) : "";
	let host = collapseSlashes(prefix.substring(protocol.length, prefix.length));
	if (host.startsWith("/")) { host = host.substring(1, host.length); }
	const mark = url.indexOf("?");
	const normalized = mark < 0
		? collapseSlashes(url)
		: collapseSlashes(url.substring(0, mark)) + url.substring(mark, url.length);
	if (!normalized.startsWith(protocol)) { return null; }
	let at = protocol.length;
	while (at < normalized.length && normalized.charAt(at) === "/") { at += 1; }
	const end = matchHost(host.split("."), 0, normalized, at, host === "" || host.endsWith("/"));
	if (end < 0) { return null; }
	const rest = normalized.substring(end, normalized.length);
	return rest.startsWith("?") || rest.startsWith("#") ? "/" + rest : rest;
}

export function pathOf(url: string, prefixes: string[]): string | null {
	for (const prefix of prefixes) {
		const path = pathAfterPrefix(url, prefix);
		if (path !== null) { return path; }
	}
	return null;
}

export function targetFromPath(path: string, config: LinkingConfig): NavTarget | null {
	let route = path;
	let query = "";
	const hash = route.indexOf("#");
	if (hash >= 0) { route = route.substring(0, hash); }
	const mark = route.indexOf("?");
	if (mark >= 0) {
		query = route.substring(mark + 1, route.length);
		route = route.substring(0, mark);
	}
	const parts = splitPath(route);
	const candidates: Candidate[] = [];
	collect(config.screens, [], [], candidates);
	let best: Candidate | null = null;
	let bestValues: QueryParams[] = [];
	for (const candidate of candidates) {
		const values: QueryParams[] = [];
		for (let i = 0; i < candidate.chain.length; i += 1) {
			values.push(new QueryParams());
		}
		if (!matchFrom(candidate.segments, 0, parts, 0, values)) { continue; }
		if (best === null || candidate.score > (best as Candidate).score) {
			best = candidate;
			bestValues = values;
		}
	}
	if (best === null) { return null; }
	const chosen = best as Candidate;
	const leaf = bestValues[bestValues.length - 1];
	parseQuery(query, leaf);
	let target: NavTarget | null = null;
	for (let i = chosen.chain.length - 1; i >= 0; i -= 1) {
		const values = bestValues[i];
		target = { name: chosen.chain[i], values: values.count() > 0 ? values : null, child: target, pop: target !== null };
	}
	return target;
}

export function targetFromURL(url: string, options: LinkingOptions): NavTarget | null {
	const path = pathOf(url, options.prefixes);
	if (path === null) { return null; }
	return targetFromPath(path as string, options.config);
}

function findScreen(screens: LinkingScreen[], name: string): LinkingScreen | null {
	for (const screen of screens) {
		if (screen.name === name) { return screen; }
	}
	return null;
}

function unclaimedKeys(held: QueryParams, segments: Segment[], depth: int32): string[] {
	const keys: string[] = [];
	for (const key of held.names) {
		if (keys.indexOf(key) >= 0) { continue; }
		let claimed = false;
		for (const segment of segments) {
			if (segment.param && segment.owner === depth && segment.text === key) {
				claimed = true;
			}
		}
		if (!claimed) { keys.push(key); }
	}
	keys.sort();
	return keys;
}

function unclaimedQuery(
	params: QueryParams | null,
	segments: Segment[],
	depth: int32,
): string {
	if (params === null) { return ""; }
	const held = params as QueryParams;
	const keys = unclaimedKeys(held, segments, depth);
	const pairs: string[] = [];
	for (const key of keys) {
		for (const value of held.getAll(key)) {
			pairs.push(encodeRouteComponent(key) + "=" + encodeRouteComponent(value));
		}
	}
	return pairs.join("&");
}

export function pathFromState(state: NavigationState, config: LinkingConfig): string | null {
	if (state.routes.length === 0) { return null; }
	let path = "";
	let query = "";
	let current: NavigationState | null = state;
	while (current !== null) {
		const here = current as NavigationState;
		let route = here.routes[here.index];
		let hit = findScreen(config.screens, route.name);
		let segments: Segment[] = [];
		const owned: (QueryParams | null)[] = [];
		while (hit !== null) {
			const screen = hit as LinkingScreen;
			segments = screenSegments(screen, segments, owned.length as int32);
			owned.push(route.params);
			const nested = route.state;
			const children = screen.screens;
			if (nested === null || children === null) { break; }
			const inner = nested as NavigationState;
			const next = inner.routes[inner.index];
			const child = findScreen(children as LinkingScreen[], next.name);
			if (child === null) { break; }
			route = next;
			hit = child;
		}
		const depth = (owned.length as int32) - 1;
		if (depth < 0) {
			path += "/" + encodeRouteComponent(route.name);
		} else {
			const pieces: string[] = [];
			for (const segment of segments) {
				if (segment.wildcard) {
					pieces.push(encodeRouteComponent(route.name));
				} else if (!segment.param) {
					pieces.push(encodeRouteComponent(segment.text));
				} else {
					const values = owned[segment.owner];
					let value: string | null = null;
					if (values !== null) {
						value = (values as QueryParams).get(segment.text);
					}
					if (value !== null) {
						pieces.push(encodeRouteComponent(value as string));
					} else if (!segment.optional) {
						return null;
					}
				}
			}
			path += "/" + pieces.join("/");
		}
		const rest = route.state;
		if (rest === null) { query = unclaimedQuery(route.params, segments, depth); }
		current = rest;
	}
	path = "/" + splitPath(path).join("/");
	return query === "" ? path : path + "?" + query;
}

function ownSegments(screens: LinkingScreen[] | null, name: string): Segment[] | null {
	const screen = screens === null ? null : findScreen(screens as LinkingScreen[], name);
	if (screen === null) { return null; }
	const own = (screen as LinkingScreen).path;
	return own === null ? [] : patternSegments(own as string, 0);
}

export function screenPathPart(
	screens: LinkingScreen[] | null,
	name: string,
	values: QueryParams | null,
): string {
	const segments = ownSegments(screens, name);
	if (segments === null) { return encodeRouteComponent(name); }
	const pieces: string[] = [];
	for (const segment of segments as Segment[]) {
		if (segment.wildcard) {
			pieces.push(encodeRouteComponent(name));
		} else if (!segment.param) {
			pieces.push(encodeRouteComponent(segment.text));
		} else {
			let value: string | null = null;
			if (values !== null) { value = (values as QueryParams).get(segment.text); }
			if (value !== null) {
				pieces.push(encodeRouteComponent(value as string));
			} else if (!segment.optional) {
				throw new Error(
					"linking: screen '" + name + "' has no value for its path param ':" +
					segment.text + "'",
				);
			}
		}
	}
	return pieces.join("/");
}

export function screenQuery(
	screens: LinkingScreen[] | null,
	name: string,
	values: QueryParams | null,
): QueryParams | null {
	if (values === null) { return null; }
	const held = values as QueryParams;
	const segments = ownSegments(screens, name);
	const query = new QueryParams();
	for (const key of unclaimedKeys(held, segments === null ? [] : segments as Segment[], 0)) {
		for (const value of held.getAll(key)) { query.append(key, value); }
	}
	return query;
}

export function nestedScreens(screens: LinkingScreen[] | null, name: string): LinkingScreen[] | null {
	const screen = screens === null ? null : findScreen(screens as LinkingScreen[], name);
	return screen === null ? null : (screen as LinkingScreen).screens;
}
