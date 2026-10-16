import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { createAsyncMemo, createMemo } from "../../src/core/memo";
import { Accessor } from "../../src/core/signal";
import { Loading } from "../../src/macros/ui/flow";
import { streamRender } from "../../src/render/ssr";

const waiting: NeonNode = el("b", [], [], text("loading"));
const fetches: string[] = [];

async function after(ms: int32, value: int32): Promise<int32> {
	await sleepAsync(ms);
	return value;
}

function fetched(name: string): int32 {
	let n = 0;
	for (const f of fetches) { if (f === name) { n += 1; } }
	return n;
}

function slow(name: string, ms: int32, value: int32): Accessor<int32> {
	return createAsyncMemo((p: int32 | null): Promise<int32> => {
		fetches.push(name);
		return after(ms, value);
	});
}

let lastRecords = "";

async function rendered(view: NeonNode): Promise<string> {
	const r = streamRender(view);
	await r.finished;
	const failure = r.failure;
	lastRecords = r.result.records;
	return failure === null ? r.result.html : "FAILED: " + failure.message;
}

test "a Loading over a memo created outside it settles when the content reads it in its body" {
	const view: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = slow("body", 5, 7);
		const content: NeonNode = (h: Host, p: HostNode, b: HostNode | null): void => {
			const v = data();
			el("p", [], [], text("v=" + v.toString()))(h, p, b);
		};
		Loading({ children: content, fallback: waiting })(host, parent, before);
	};
	const html = await rendered(view);
	assert html === "<p>v=7</p><!---->", html;
	assert lastRecords.includes("]=\"7\"</script>"), lastRecords;
	assert fetched("body") === 1, "compute ran " + fetched("body").toString() + " times";
}

test "a Loading over a memo created outside it settles when a text spot reads it" {
	const view: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = slow("spot", 5, 7);
		Loading({ children: el("p", [], [], dynText((): string => "v=" + data().toString())), fallback: waiting })(host, parent, before);
	};
	const html = await rendered(view);
	assert html === "<p>v=7</p><!---->", html;
	assert lastRecords.includes("]=\"7\"</script>"), lastRecords;
	assert fetched("spot") === 1, "compute ran " + fetched("spot").toString() + " times";
}

test "a Loading over a memo of a memo, both created outside it, waits on the async source and settles" {
	const view: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const inner = slow("deep", 5, 7);
		const outer = createMemo((p: int32 | null): int32 => inner() + 1);
		Loading({ children: el("p", [], [], dynText((): string => "v=" + outer().toString())), fallback: waiting })(host, parent, before);
	};
	const html = await rendered(view);
	assert html === "<p>v=8</p><!---->", html;
	assert fetched("deep") === 1, "compute ran " + fetched("deep").toString() + " times";
}

test "a root read of a memo of a memo, with no Loading, waits on the async source and settles" {
	const view: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const inner = slow("rootDeep", 5, 7);
		const outer = createMemo((p: int32 | null): int32 => inner() + 1);
		el("p", [], [], dynText((): string => "v=" + outer().toString()))(host, parent, before);
	};
	const html = await rendered(view);
	assert html === "<p>v=8</p>", html;
	assert fetched("rootDeep") === 1, "compute ran " + fetched("rootDeep").toString() + " times";
}

test "a root read of a memo created before the render began fails naming the source with no slot" {
	const early = slow("early", 4, 7);
	const view: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		el("p", [], [], dynText((): string => "v=" + early().toString()))(host, parent, before);
	};
	const html = await rendered(view);
	assert html.includes("SERVER_WAIT_WITHOUT_SLOT"), "[" + html + "]";
	await sleepAsync(10);
}

test "a root read behind another pending root read waits on each source in turn and computes once" {
	const view: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const first = slow("first", 3, 1);
		const second = slow("second", 12, 3);
		el("p", [], [], dynText((): string => "a=" + first().toString()))(host, parent, before);
		el("p", [], [], dynText((): string => "b=" + second().toString()))(host, parent, before);
	};
	const html = await rendered(view);
	assert html === "<p>a=1</p><p>b=3</p>", html;
	assert fetched("first") === 1 && fetched("second") === 1, "compute ran " + fetched("first").toString() + "/" + fetched("second").toString() + " times";
}
