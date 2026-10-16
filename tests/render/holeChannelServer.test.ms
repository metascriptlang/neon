import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { createAsyncMemo, createMemo } from "../../src/core/memo";
import { Loading, Errored } from "../../src/macros/ui/flow";
import { Accessor } from "../../src/core/signal";
import { renderToStream, streamRender, SafeError } from "../../src/render/ssr";

const waiting: NeonNode = el("b", [], [], text("loading"));
const fetches: string[] = [];
const bodies: string[] = [];

async function afterStr(ms: int32, value: string): Promise<string> {
	await sleepAsync(ms);
	return value;
}

function fetched(name: string): int32 {
	let n = 0;
	for (const f of fetches) { if (f === name) { n += 1; } }
	return n;
}

function ran(name: string): int32 {
	let n = 0;
	for (const b of bodies) { if (b === name) { n += 1; } }
	return n;
}

function counted(name: string, inner: NeonNode): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		bodies.push(name);
		inner(host, parent, before);
	};
}

function spot(name: string, slow: boolean, value: string, ms: int32 = 3): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		if (slow) {
			const data = createAsyncMemo((p: string | null): Promise<string> => {
				fetches.push(name);
				return afterStr(ms, value);
			});
			dynText((): string => data())(host, parent, before);
		} else {
			const data = createMemo((p: string | null): string => value);
			dynText((): string => data())(host, parent, before);
		}
	};
}

function parityPage(key: string, parts: string[], slow: boolean): NeonNode {
	const content: NeonNode = counted(key, (host: Host, parent: HostNode, before: HostNode | null): void => {
		for (const part of parts) {
			if (part.startsWith("t:")) {
				text(part.slice(2))(host, parent, before);
			} else {
				spot(key + part, slow, part.slice(2))(host, parent, before);
			}
		}
	});
	return el("p", [], [], (host: Host, parent: HostNode, before: HostNode | null): void => {
		text("lead")(host, parent, before);
		Loading({ children: content, fallback: waiting })(host, parent, before);
		text("tail")(host, parent, before);
	});
}

async function parity(key: string, parts: string[]): Promise<string> {
	const held = await renderToStream(parityPage(key + "-held", parts, true));
	const once = await renderToStream(parityPage(key + "-once", parts, false));
	if (held.html !== once.html) { return key + ": [" + held.html + "] against [" + once.html + "]"; }
	if (ran(key + "-held") !== 1) { return key + ": the content body ran " + ran(key + "-held").toString() + " times"; }
	return "";
}

test "a Loading whose text spots pend writes the bytes a ready one writes and runs its body once" {
	let bad = "";
	bad += await parity("value", ["h:v"]);
	bad += await parity("empty", ["h:"]);
	bad += await parity("before", ["t:a", "h:v"]);
	bad += await parity("beforeEmpty", ["t:a", "h:"]);
	bad += await parity("after", ["h:v", "t:b"]);
	bad += await parity("afterEmpty", ["h:", "t:b"]);
	bad += await parity("chain", ["h:v", "h:w"]);
	bad += await parity("chainEmpty", ["h:", "h:w", "h:", "t:b"]);
	assert bad === "", bad;
}

test "a memo made in the Loading body and read in a spot of a nested component computes once and the body runs once" {
	const child = (data: () => string): NeonNode => counted("profileChild", el("p", [], [], dynText((): string => "name=" + data())));
	const content: NeonNode = counted("profileBody", (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: string | null): Promise<string> => {
			fetches.push("profile");
			return afterStr(6, "ada");
		});
		child((): string => data())(host, parent, before);
	});
	const out = await renderToStream(Loading({ children: content, fallback: waiting }));
	assert out.html === "<p>name=ada</p><!---->", out.html;
	assert ran("profileBody") === 1 && ran("profileChild") === 1, ran("profileBody").toString() + "/" + ran("profileChild").toString();
	assert fetched("profile") === 1, "computed " + fetched("profile").toString() + " times";
	assert out.records.includes("ada"), out.records;
}

test "a memo made outside the Loading and a second spot that settles later: the body runs once and each computes once" {
	const app: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const outer = createAsyncMemo((p: string | null): Promise<string> => {
			fetches.push("outerMemo");
			return afterStr(4, "o");
		});
		const content: NeonNode = counted("twoPass", (h: Host, p: HostNode, b: HostNode | null): void => {
			el("p", [], [], dynText((): string => "o=" + outer()))(h, p, b);
			el("p", [], [], (h2: Host, p2: HostNode, b2: HostNode | null): void => {
				const late = createAsyncMemo((q: string | null): Promise<string> => {
					fetches.push("lateMemo");
					return afterStr(20, "l");
				});
				dynText((): string => "l=" + late())(h2, p2, b2);
			})(h, p, b);
		});
		Loading({ children: content, fallback: waiting })(host, parent, before);
	};
	const out = await renderToStream(app);
	assert out.html === "<p>o=o</p><p>l=l</p><!---->", out.html;
	assert ran("twoPass") === 1, "the body ran " + ran("twoPass").toString() + " times";
	assert fetched("outerMemo") === 1 && fetched("lateMemo") === 1, fetched("outerMemo").toString() + "/" + fetched("lateMemo").toString();
}

test "a text spot in a script falls back to the body channel and still settles" {
	const content: NeonNode = counted("rawBody", el("script", [], [], spot("rawSpot", true, "v")));
	const out = await renderToStream(Loading({ children: content, fallback: waiting }));
	assert out.html === "<script>v</script><!---->", out.html;
	assert ran("rawBody") === 2 && fetched("rawSpot") === 1, "the body ran " + ran("rawBody").toString() + " times; fetched " + fetched("rawSpot").toString();
}

test "a nested Loading that settles before the Loading holding its placeholder is written after it" {
	const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		el("p", [], [], spot("nestOuter", true, "o", 40))(host, parent, before);
		Loading({ children: el("i", [], [], spot("nestInner", true, "n", 3)), fallback: waiting })(host, parent, before);
	};
	const chunks: string[] = [];
	const r = streamRender(Loading({ children: content, fallback: waiting }));
	r.pipe({ write: (chunk: string): void => { chunks.push(chunk); }, end: (): void => {} });
	await r.markup();
	let swaps = 0;
	let first = "";
	for (const c of chunks) {
		if (c.indexOf("$df(") < 0) { continue; }
		swaps += 1;
		if (first === "") { first = c; }
	}
	assert swaps === 2, "two swaps: " + chunks.join(" || ");
	assert first.indexOf("<template id=\"pl-") >= 0, "the first swap carries the inner placeholder: " + first;
}

async function failAfter(ms: int32): Promise<int32> {
	await sleepAsync(ms);
	throw new SafeError("nope");
}

test "a text spot that fails once its source has settled takes the body channel, so the Errored around it catches the error" {
	const failing: NeonNode = counted("failBody", (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => {
			fetches.push("failSpot");
			return failAfter(4);
		});
		el("p", [], [], dynText((): string => data().toString()))(host, parent, before);
	});
	const view = Loading({
		children: Errored({
			children: failing,
			fallback: (err: Accessor<Error>, reset: () => void): NeonNode => el("em", [], [], text("caught " + err().message)),
		}),
		fallback: waiting,
	});
	const out = await renderToStream(view);
	assert out.html.includes("<em>caught nope</em>") && !out.html.includes("<p>"), out.html;
	assert ran("failBody") === 2, "the hole channel once, the body channel once: " + ran("failBody").toString();
}
