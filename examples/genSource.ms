extern class XMLHttpRequest {
	status: number;
	responseText: string;
	extern open(method: cstring, url: cstring, isAsync: boolean): void;
	extern send(): void;
}

const EMITTED_MODULE = "/node_modules/.metascript/examples/counterDom.js";

function isIdentCode(c: int32): boolean {
	return (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c === 95;
}

function isDigitCode(c: int32): boolean {
	return c >= 48 && c <= 57;
}

function shorten(w: string): string {
	if (w.indexOf("Z85sers", 0) > 0) {
		const cut = w.indexOf("__", 0);
		if (cut > 0) {
			return w.slice(0, cut);
		}
	}
	let end = w.length;
	while (end > 0 && isDigitCode(w.charCodeAt(end - 1))) {
		end = end - 1;
	}
	if (end >= 2 && end < w.length && w.charCodeAt(end - 1) === 117 && w.charCodeAt(end - 2) === 95) {
		return w.slice(0, end - 2);
	}
	return w;
}

function demangle(src: string): string {
	let out = "";
	let i = 0;
	const n = src.length;
	while (i < n) {
		if (isIdentCode(src.charCodeAt(i))) {
			let j = i;
			while (j < n && isIdentCode(src.charCodeAt(j))) {
				j = j + 1;
			}
			out = out + shorten(src.slice(i, j));
			i = j;
		} else {
			out = out + src.slice(i, i + 1);
			i = i + 1;
		}
	}
	return out;
}

function skipSpace(src: string, from: int32): int32 {
	let i = from;
	const n = src.length;
	while (i < n) {
		const c = src.charCodeAt(i);
		if (c !== 32 && c !== 9 && c !== 10 && c !== 13) {
			return i;
		}
		i = i + 1;
	}
	return n;
}

function trimEnd(s: string): string {
	let end = s.length;
	while (end > 0) {
		const c = s.charCodeAt(end - 1);
		if (c !== 32 && c !== 9 && c !== 10 && c !== 13) {
			return s.slice(0, end);
		}
		end = end - 1;
	}
	return "";
}

function indent(depth: int32): string {
	let s = "";
	let i = 0;
	while (i < depth) {
		s = s + "  ";
		i = i + 1;
	}
	return s;
}

function isSubscriptStart(c: int32): boolean {
	return isIdentCode(c) || c === 41 || c === 93;
}

function pretty(src: string): string {
	let out = "";
	let depth = 0;
	let quote = 0;
	let subscripts = 0;
	let i = 0;
	const n = src.length;
	while (i < n) {
		const c = src.charCodeAt(i);
		const ch = src.slice(i, i + 1);
		if (quote !== 0) {
			out = out + ch;
			if (c === 92) {
				out = out + src.slice(i + 1, i + 2);
				i = i + 2;
				continue;
			}
			if (c === quote) {
				quote = 0;
			}
			i = i + 1;
			continue;
		}
		if (c === 34 || c === 39 || c === 96) {
			quote = c;
			out = out + ch;
			i = i + 1;
			continue;
		}
		if (c === 123 || c === 91) {
			const close = c === 123 ? 125 : 93;
			const j = skipSpace(src, i + 1);
			if (j < n && src.charCodeAt(j) === close) {
				out = out + ch + src.slice(j, j + 1);
				i = j + 1;
				continue;
			}
			if (c === 91 && i > 0 && isSubscriptStart(src.charCodeAt(i - 1))) {
				subscripts = subscripts + 1;
				out = out + ch;
				i = i + 1;
				continue;
			}
			depth = depth + 1;
			out = out + ch + "\n" + indent(depth);
			i = j;
			continue;
		}
		if (c === 125 || c === 93) {
			if (c === 93 && subscripts > 0) {
				subscripts = subscripts - 1;
				out = out + ch;
				i = i + 1;
				continue;
			}
			depth = depth > 0 ? depth - 1 : 0;
			out = trimEnd(out) + "\n" + indent(depth) + ch;
			i = i + 1;
			continue;
		}
		if (c === 40) {
			depth = depth + 1;
			out = out + ch;
			i = i + 1;
			continue;
		}
		if (c === 41) {
			depth = depth > 0 ? depth - 1 : 0;
			out = out + ch;
			i = i + 1;
			continue;
		}
		if (c === 44 || c === 59) {
			out = out + ch + "\n" + indent(depth);
			i = skipSpace(src, i + 1);
			continue;
		}
		if (c === 32 || c === 9 || c === 10 || c === 13) {
			out = out + " ";
			i = skipSpace(src, i);
			continue;
		}
		out = out + ch;
		i = i + 1;
	}
	return out;
}

function fetchEmitted(): string {
	const req = new XMLHttpRequest();
	req.open("GET", EMITTED_MODULE, false);
	req.send();
	if (req.status !== 200) {
		return "";
	}
	return req.responseText;
}

export function generatedMain(): string {
	const js = fetchEmitted();
	if (js === "") {
		return `no emitted module at ${EMITTED_MODULE} — run the Vite dev server`;
	}
	const start = js.indexOf("function main_", 0);
	if (start < 0) {
		return "no main_ in the emitted module";
	}
	const end = js.indexOf("\n}", start);
	const body = end < 0 ? js.slice(start, js.length) : js.slice(start, end + 2);
	return pretty(demangle(body));
}
