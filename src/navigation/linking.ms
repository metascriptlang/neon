import { NavTarget } from "./core";

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
		const exact = screen.exact;
		const fromRoot = exact !== null && (exact as boolean);
		let segments: Segment[] = fromRoot ? [] : prefix.slice(0, prefix.length);
		if (own !== null) {
			for (const segment of patternSegments(own as string, depth)) { segments.push(segment); }
		}
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

export function decodeComponent(text: string): string {
	if (text.indexOf("%") < 0) { return text; }
	const bytes: uint8[] = [];
	const length = text.byteLength();
	let i: int32 = 0;
	while (i < length) {
		const byte = text.byteAt(i);
		if (byte === 37 && i + 2 < length) {
			const high = hexValue(text.byteAt(i + 1));
			const low = hexValue(text.byteAt(i + 2));
			if (high >= 0 && low >= 0) {
				bytes.push((high * 16 + low) as uint8);
				i += 3;
				continue;
			}
		}
		bytes.push(byte as uint8);
		i += 1;
	}
	return bytes.asString();
}

function decode(text: string): string {
	return decodeComponent(text);
}

function matchFrom(
	segments: Segment[],
	from: int32,
	parts: string[],
	at: int32,
	values: Map<string, string>[],
): boolean {
	if (from >= segments.length) { return at >= parts.length; }
	const segment = segments[from];
	if (segment.wildcard) { return true; }
	if (segment.param) {
		if (at < parts.length) {
			values[segment.owner].set(segment.text, decode(parts[at]));
			if (matchFrom(segments, from + 1, parts, at + 1, values)) { return true; }
			values[segment.owner].delete(segment.text);
		}
		return segment.optional && matchFrom(segments, from + 1, parts, at, values);
	}
	if (at >= parts.length || parts[at] !== segment.text) { return false; }
	return matchFrom(segments, from + 1, parts, at + 1, values);
}

export function pathOf(url: string, prefixes: string[]): string | null {
	let best: string | null = null;
	let bestLength = -1;
	for (const prefix of prefixes) {
		if (url.startsWith(prefix) && prefix.length > bestLength) {
			best = url.substring(prefix.length, url.length);
			bestLength = prefix.length;
		}
	}
	return best;
}

export function targetFromPath(path: string, config: LinkingConfig): NavTarget | null {
	let route = path;
	let query = "";
	const mark = route.indexOf("?");
	if (mark >= 0) {
		query = route.substring(mark + 1, route.length);
		route = route.substring(0, mark);
	}
	const hash = route.indexOf("#");
	if (hash >= 0) { route = route.substring(0, hash); }
	const parts = splitPath(route);
	const candidates: Candidate[] = [];
	collect(config.screens, [], [], candidates);
	let best: Candidate | null = null;
	let bestValues: Map<string, string>[] = [];
	for (const candidate of candidates) {
		const values: Map<string, string>[] = [];
		for (let i = 0; i < candidate.chain.length; i += 1) {
			values.push(new Map<string, string>());
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
	if (query !== "") {
		for (const pair of query.split("&")) {
			if (pair === "") { continue; }
			const eq = pair.indexOf("=");
			if (eq < 0) {
				leaf.set(decode(pair), "");
			} else {
				const key = decode(pair.substring(0, eq));
				leaf.set(key, decode(pair.substring(eq + 1, pair.length)));
			}
		}
	}
	let target: NavTarget | null = null;
	for (let i = chosen.chain.length - 1; i >= 0; i -= 1) {
		const values = bestValues[i];
		target = { name: chosen.chain[i], values: values.size > 0 ? values : null, child: target };
	}
	return target;
}

export function targetFromURL(url: string, options: LinkingOptions): NavTarget | null {
	const path = pathOf(url, options.prefixes);
	if (path === null) { return null; }
	return targetFromPath(path as string, options.config);
}
