import { decodeRouteComponent } from "./routing";

export interface PathMatch {
	path: string;
	params: Map<string, string>;
}

export function normalizePath(path: string, omitSlash: boolean = false): string {
	let start: int32 = 0;
	while (start < path.length && path[start] === "/") { start += 1; }
	let end = path.length;
	let trailing: int32 = 0;
	while (end - trailing > start && path[end - trailing - 1] === "/") { trailing += 1; }
	if (trailing >= 2) { end = end - trailing + 1; }
	const s = path.substring(start, end);
	if (s === "") { return ""; }
	return omitSlash || s.startsWith("?") || s.startsWith("#") ? s : "/" + s;
}

function stripSplat(path: string): string {
	for (let p: int32 = 0; p < path.length; p += 1) {
		let q = p;
		while (q < path.length && path[q] === "/") { q += 1; }
		if (q === path.length || path[q] === "*") { return path.substring(0, p); }
	}
	return path;
}

export function joinPaths(from: string, to: string): string {
	return stripSplat(normalizePath(from)) + normalizePath(to);
}

export function hasScheme(path: string): boolean {
	let at: int32 = 0;
	while (at < path.length) {
		const code = path.charCodeAt(at);
		if (!((code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122))) { break; }
		at += 1;
	}
	if (at < path.length && path[at] === ":") { at += 1; }
	else { at = 0; }
	return path.substring(at, path.length).startsWith("//");
}

function removeDotSegments(address: string): string {
	let end = address.length;
	const query = address.indexOf("?");
	const hash = address.indexOf("#");
	if (query >= 0) { end = query; }
	if (hash >= 0 && hash < end) { end = hash; }
	const kept: string[] = [];
	const parts = address.substring(0, end).split("/");
	for (let i = 1; i < parts.length; i += 1) {
		const last = i === parts.length - 1;
		if (parts[i] === "." || parts[i] === "..") {
			if (parts[i] === ".." && kept.length > 0) { kept.pop(); }
			if (last) { kept.push(""); }
		} else {
			kept.push(parts[i]);
		}
	}
	return "/" + kept.join("/") + address.substring(end, address.length);
}

export function resolvePath(base: string, path: string, from: string): string | null {
	if (hasScheme(path)) { return null; }
	const basePath = normalizePath(base);
	const fromPath = normalizePath(from);
	let result = "";
	if (fromPath === "" || path.startsWith("/")) {
		result = basePath;
	} else if (fromPath.toLowerCase().indexOf(basePath.toLowerCase()) !== 0) {
		result = basePath + fromPath;
	} else {
		result = fromPath;
	}
	return removeDotSegments((result === "" ? "/" : result) + normalizePath(path, result === ""));
}

function beforeSplat(path: string): string {
	const star = path.indexOf("/*");
	return star < 0 ? path : path.substring(0, star);
}

function splatOf(path: string): string | null {
	const star = path.indexOf("/*");
	if (star < 0) { return null; }
	const rest = path.substring(star + 2, path.length);
	const next = rest.indexOf("/*");
	return next < 0 ? rest : rest.substring(0, next);
}

function segmentsOf(pattern: string): string[] {
	const segments: string[] = [];
	for (const segment of pattern.split("/")) {
		if (segment !== "") { segments.push(segment); }
	}
	return segments;
}

export function createMatcher(
	path: string,
	partial: boolean = false,
): (location: string) => PathMatch | null {
	const splat = splatOf(path);
	const segments = segmentsOf(beforeSplat(path));
	const len = segments.length;
	return (location: string): PathMatch | null => {
		const parts = location.split("/");
		const first: int32 = parts[0] === "" ? 1 : 0;
		let last = parts.length;
		if (last > first && parts[last - 1] === "") { last -= 1; }
		for (let i = first; i < last; i += 1) {
			if (parts[i] === "") { return null; }
		}
		const lenDiff = last - first - len;
		if (lenDiff < 0 || (lenDiff > 0 && splat === null && !partial)) { return null; }
		const params = new Map<string, string>();
		let matched = len > 0 ? "" : "/";
		for (let i: int32 = 0; i < len; i += 1) {
			const segment = segments[i];
			const part = parts[first + i];
			if (segment.startsWith(":")) {
				const value = decodeRouteComponent(part);
				if (!value.ok) { return null; }
				params.set(segment.substring(1, segment.length), value.value);
				matched += "/" + part;
			} else {
				const lower = part.toLowerCase();
				if (lower !== segment.toLowerCase()) { return null; }
				matched += "/" + lower;
			}
		}
		if (splat !== null && splat !== "") {
			const remainder = lenDiff > 0 ? parts.slice(last - lenDiff, last).join("/") : "";
			const value = decodeRouteComponent(remainder);
			if (!value.ok) { return null; }
			params.set(splat as string, value.value);
		}
		return { path: matched, params };
	};
}

export function scoreRoute(pattern: string): int32 {
	const segments = segmentsOf(beforeSplat(pattern));
	let score: int32 = segments.length - (splatOf(pattern) === null ? 0 : 1);
	for (const segment of segments) { score += segment.startsWith(":") ? 2 : 3; }
	return score;
}

function optionalAt(pattern: string, from: int32, anchored: boolean): [int32, int32] {
	for (let start = from; start < pattern.length; start += 1) {
		const colon = pattern[start] === "/" && pattern[start + 1] === ":" ? start + 1 : start;
		if (pattern[colon] === ":" && (colon > start || !anchored)) {
			let stop = colon + 1;
			while (stop < pattern.length && pattern[stop] !== "/") { stop += 1; }
			const mark = pattern.substring(colon + 2, stop).lastIndexOf("?");
			if (mark >= 0) { return [start, colon + 2 + mark - start]; }
		}
		if (anchored) { break; }
	}
	return [-1, 0];
}

export function expandOptionals(pattern: string): string[] {
	const [at, size] = optionalAt(pattern, 0, false);
	if (at < 0) { return [pattern]; }
	let prefix = pattern.substring(0, at);
	let suffix = pattern.substring(at + size + 1, pattern.length);
	const prefixes: string[] = [prefix];
	prefix += pattern.substring(at, at + size);
	prefixes.push(prefix);
	while (true) {
		const [next, length] = optionalAt(suffix, 0, true);
		if (next < 0) { break; }
		prefix += suffix.substring(0, length);
		prefixes.push(prefix);
		suffix = suffix.substring(length + 1, suffix.length);
	}
	const results: string[] = [];
	for (const expansion of expandOptionals(suffix)) {
		for (const start of prefixes) { results.push(start + expansion); }
	}
	return results;
}

function keptLiteral(byte: int32): boolean {
	return (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) ||
		(byte >= 48 && byte <= 57) || byte === 45 || byte === 95 || byte === 46 ||
		byte === 33 || byte === 126 || (byte >= 36 && byte <= 44 && byte !== 37) ||
		byte === 58 || byte === 59 || byte === 61 || byte === 64;
}

function encodeSegment(segment: string): string {
	const hex = "0123456789ABCDEF";
	let encoded = "";
	for (let i: int32 = 0; i < segment.byteLength(); i += 1) {
		const byte = segment.byteAt(i);
		if (keptLiteral(byte)) {
			encoded += String.fromCharCode(byte);
		} else {
			encoded += "%" + hex.substring(byte / 16, byte / 16 + 1) +
				hex.substring(byte % 16, byte % 16 + 1);
		}
	}
	return encoded;
}

export function encodePattern(pattern: string): string {
	const parts: string[] = [];
	for (const part of pattern.split("/")) {
		parts.push(part.startsWith(":") || part.startsWith("*") ? part : encodeSegment(part));
	}
	return parts.join("/");
}

export function routePatterns(path: string, base: string, leaf: boolean): string[] {
	const patterns: string[] = [];
	for (const expanded of expandOptionals(path)) {
		const joined = joinPaths(base, expanded);
		patterns.push(encodePattern(leaf ? joined : beforeSplat(joined)));
	}
	return patterns;
}
